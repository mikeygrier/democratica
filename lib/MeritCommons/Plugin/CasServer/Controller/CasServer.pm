#    MeritCommons Portal
#    Copyright 2013 Wayne State University
#    All Rights Reserved

package MeritCommons::Plugin::CasServer::Controller::CasServer;
use MeritCommons::Plugin::CasServer::ServiceResponse;

# we're a Mojolicious::Controller, first and foremost!
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw(b64_encode url_escape url_unescape);
use Mojo::UserAgent;
use Mojo::URL;

# declare our @ISA and make sure we can call our plugin config method
our @ISA;
push(@ISA, 'MeritCommons::Plugin');

sub test {
    my ($self) = @_;

    $self->render(text => $self->dumper($self->casserver->plugin_config));
}

sub login {
    my ($self) = @_;

    # make sure we never cache these pages.
    $self->tx->res->headers->cache_control('max-age=1, no-cache');
    
    my $service = $self->param('service');

    # if a target parameter was passed, then SAML11 authentication is requested
    my $target = $self->param('TARGET');
    my $saml11 = ($target) ? 1 : 0;

    if ($saml11) {
        $service = $target;
    }

    # any gateway/renew/warn value, regardless of what the value is, is considered true
    my $gateway = $self->param('gateway') ? 1 : 0;
    my $renew   = $self->param('renew')   ? 1 : 0;
    my $warn    = $self->param('warn')    ? 1 : 0;

    if ($warn) {
        my $redirect_url = "/cas/login";

        # Add parameters back to the URL if defined
        my @params;
        push(@params, "service=" . url_escape($service)) if $service;
        push(@params, "TARGET=" . url_escape($target))   if $target;
        push(@params, "renew=1")                         if $renew;
        push(@params, "gateway=1")                       if $gateway;

        if (scalar(@params) > 0) {
            $redirect_url = $redirect_url . "?" . join("&", @params);
        }

        $self->stash('redirect_url', $redirect_url);
        $self->render(template => "casserver_auth/authentication_warning");
    } else {
        if ($self->active_user && !$renew && ($self->meritcommons_session->cas_session_expire->first > time)) {
            $self->_login_authenticated($service, $renew, $saml11);
        } else {
            if ($gateway && $service) {

                # If a user cannot be authenticated through non-interactive means, they should
                # be rerouted back to the service without a ticket
                $self->redirect_to($service);
            } else {
                $self->_render_login_form($service, $renew);
            }
        }
    }
}

sub _render_login_form {
    my ($self, $service, $renew) = @_;

    my $login_ticket = "LT-" . $self->app->new_uuid;
    $self->session('cas_login_ticket', $login_ticket);

    $self->stash(login_ticket => $login_ticket);
    $self->stash(service      => $service);
    $self->stash(renew        => $renew);
    $self->stash(message      => "Please enter your credentials");
    $self->render(template => "casserver_auth/login");
}

sub login_submit {
    my ($self) = @_;

    my $service  = $self->param('service');

    # if a target parameter was passed, then SAML11 authentication is requested
    my $target = $self->param('TARGET');
    my $saml11 = ($target) ? 1 : 0;

    if ($saml11) {
        $service = $target;
    }

    my $renew    = ($self->param('renew') eq "1") ? 1 : 0;
    my $username = $self->param('username');
    my $password = $self->param('password');
    my $lt       = $self->param('lt');

    if ($lt eq $self->session('cas_login_ticket')) {
        my @session = $self->new_session("initial_login", $username, $password, $renew);
        if ($session[0]) {
            $self->_login_authenticated($service, $renew, $saml11);
        } else {
            $self->_render_login_form($service, $renew);
        }
    } else {

        # Login ticket did not match, let them try again (maybe they had two logins open)
        $self->_render_login_form($service, $renew);
    }
}

sub cancel_authentication {
    my ($self) = @_;

    $self->stash('message', "You have cancelled the authentication process.");
    $self->render(template => "casserver_auth/message");
}

# Common logic for after a user is successfully authenticated by either SSO or a login
sub _login_authenticated {
    my ($self, $service, $renew, $saml11) = @_;

    $service = $self->strip_jsession($service);

    $self->app->emit('cas_before_login_authenticated', $self, $service);

    if (my $url = $self->stash('further_auth_required')) {
        $self->redirect_to($url);
        return;
    }

    if ($service) {
        my $url_permitted;
        if ($self->casserver->plugin_config->{enable_whitelist} && ($self->casserver->plugin_config->{enable_whitelist} == 1)) {
            $url_permitted = $self->casserver->whitelist_match($service);
        } else {
            $url_permitted = 1;
        }

        if (!$url_permitted) {
            $self->stash('message', "Service provider is not recognized");
            $self->render(template => "casserver_auth/message");
            $self->app->log->info("CasServer - URL not permitted based on whitelist rules: '$service'");
        } elsif ($self->casserver->plugin_config->{require_https} && 
              ($self->casserver->plugin_config->{require_https} == 1) && !($service =~ m/^https:\/\//i)) {
            $self->stash('message', "HTTPS is required for service provider URLs");
            $self->render(template => "casserver_auth/message");
            $self->app->log->info("CasServer plugin is configured to serve https:// services only, '$service' does not use https://");
        } else {
            # User already has an MeritCommons session.  Create a CAS ticket for them
            my $ticket = $self->casserver->create_ticket("ST", $service, time, $renew, undef, undef, $saml11);
            
            # Return the response parameters depending on if SAML11 compliant ticket IDs are being used
            my $redirect_url = Mojo::URL->new($ticket->service);

            if (!($ticket->ticket_id =~ /^ST-/)) {
                $redirect_url->query([SAMLart => $ticket->ticket_id]);
            } else {
                $redirect_url->query([ticket => $ticket->ticket_id]);
            }

            $self->app->log->info("CasServer - @{[$self->active_user->userid]} is authenticated, redirecting client to $redirect_url");

            $self->redirect_to($redirect_url);
        }
    } else {
        $self->stash('message', "You are currently authenticated");
        $self->render(template => "casserver_auth/message");
    }
}

sub logout {
    my ($self) = @_;

    my $url = $self->param('url');

    # If the user is logged in, delete all CAS tickets and log out of MeritCommons
    if ($self->active_user) {
        $self->app->casserver->delete_tickets_by_user($self->active_user);
        if ($url && $self->casserver->plugin_config->{logout_to_auth_url}) {
            my $auth_url = Mojo::URL->new($self->global_config->{auth_url});
            my $lp = $self->casserver->plugin_config->{logout_parameters};
            
            my $to_merge = [
                $self->global_config->{auth_back_param} => $url,
            ];
            
            if (ref $lp eq "HASH") {
                foreach my $key (keys %$lp) {
                    push(@$to_merge, $key, $lp->{$key});
                }
            }

            # merge these values in
            $auth_url->query($to_merge);

            $self->app->log->info("CasServer - logged out of CAS service, and 'logout_to_auth_url' is true; sending user " . 
                "to $auth_url");

            # send them on their merry way
            $self->redirect_to($auth_url);
        } else {
            $self->app->log->info("CasServer - logged out of CAS service, and 'logout_to_auth_url' configuration option " .
                "is false; clearing MeritCommons session");
            $self->destroy_session;
            $self->stash(url => $url) if ($url);
            $self->render(template => "casserver_auth/logout");
        }
    } else {
        $self->app->log->info("CasServer - agent with no session from @{[$self->tx->remote_address]} visited CAS logout " .
            "endpoint with no session");
        $self->render(text => "You are not currently signed in.");
    }
}

sub validate {
    my ($self) = @_;

    my $service   = $self->param('service');
    my $ticket_id = $self->param('ticket');
    my $renew     = ($self->param('renew')) ? 1 : 0;

    my $error  = undef;
    my $userid = undef;

    # Validate that all of the required parameters have been defined
    if (!$service || !$ticket_id) {

        # invalid parameters
        $error = 1;
    } elsif (!($ticket_id =~ /^(ST)-/)) {
        $error = 1;    # invalid type
    } else {

        # Attempt to locate the ticket
        my $ticket = $self->app->m->resultset('MeritCommons::Plugin::CasServer::Model::Ticket')->search(
            {
                ticket_id => $ticket_id,
                consumed  => 0
            }
        )->first;

        if ($ticket) {
            if (time > ($ticket->issue_time + $self->casserver->plugin_config->{ticket_expiration})) {
                $error = 1;    # ticket has expired
            } elsif (($renew == 1) && ($ticket->renew != 1)) {
                $error = 1;    # ticket must be generated through a direct login, not SSO
            } elsif ($self->strip_jsession($ticket->service) ne $self->strip_jsession($self->param('service'))) {

                # Ticket service does not match the one passed.  Per the spec, the ticket must be invalidated
                $error = 1;    # service specified does not match service associated with ticket
            } else {

                # Ticket is valid
                $userid = $ticket->meritcommons_session->meritcommons_user->userid;
            }

            $ticket->consumed(1);
            $ticket->update;    # tickets are only valid for one validation
            $self->app->log->info("CasServer - ticket for service '@{[$ticket->service]}' issued at @{[scalar $ticket->issue_time]} " . 
                "has been successfully consumed");
        } else {
            $error = 1;         # ticket not found
            $self->app->log->error("CasServer - no valid ticket found for @{[$self->param('service')]}");
        }
    }

    if ((!$error) && ($userid)) {
        $self->render(text => "yes\n$userid\n");
    } else {
        $self->render(text => "no\n\n");
    }
}

# The CAS specification states that the passed service URL "MUST" match the original service URL passed 
# to /login.  In versions of the Apereo CAS server prior to 4.1.0, there was a defect that skipped this
# validation for samlValidate:
#
# https://github.com/apereo/cas/issues/658
#
# This defect allowed for an additional ";jsessionid=" parameter to be passed in versions prior to 4.1.0 without 
# causing a validation error.  In recent versions (e.g., 4.2.1) of the Apereo CAS server, it appears that
# the validation defect was fixed, but an exception was specifically made for the jsessionid parameter.
# I was not able to find any documentation/specifications to justify this exception, although I have 
# observed the need to support jsessionid with existing applications. The jsessionid parameter is stripped 
# out to support these applications.
sub strip_jsession {
    my ($self, $url) = @_;
    $url =~ s/;jsession[^\?\b]+//;
    return $url;
}

sub saml_validate {
    my ($self) = @_;

    my $saml_request = Mojo::DOM->new($self->req->body);
    my $service_response = MeritCommons::Plugin::CasServer::ServiceResponse->new(SAML_VALIDATE_TYPE);

    # Validate that all of the required parameters have been defined
    if (!$saml_request->at('request') || 
        !$saml_request->at('request')->{'requestid'} || 
        !$saml_request->at('assertionartifact') || 
        !$saml_request->at('assertionartifact')->text || 
        !$self->param('TARGET')) {
        $service_response->add_authentication_failure("INVALID_REQUEST",
            "Not all of the required request parameters were present");
    } elsif (($saml_request->at('assertionartifact')->text =~ /^(PGT|PGTIOU|PGTIOU|PT)-/)) {
        $service_response->add_authentication_failure("INVALID_TICKET", "Invalid ticket type for method");
    } else {
        my $ticket_id = $saml_request->at('assertionartifact')->text;

        my $service = $self->param('TARGET');
        my $request_id = $saml_request->at('request')->{'requestid'};

        # Attempt to locate the ticket
        my $ticket = $self->app->m->resultset('MeritCommons::Plugin::CasServer::Model::Ticket')->search(
            {
                ticket_id => $ticket_id,
                consumed  => 0
            }
        )->first;

        # this should always match
        my $decoded_2x_service = url_unescape($service);

        # so here we have:
        # $service, which is the only thing we should be considering and we have
        # $decoded_2x_service
        
        if ($ticket) {
            if (time > ($ticket->issue_time + $self->casserver->plugin_config->{ticket_expiration})) {
                # standards compliant issued ticket validation
                $self->app->log->warn("CasServer - saml_validate - ticket issued to " . 
                    $ticket->meritcommons_session->meritcommons_user->userid . " for service '@{[$ticket->service]}' " .
                    "has expired");
                # Ticket has expired
                $service_response->add_authentication_failure("INVALID_TICKET", "Ticket has expired");
            } elsif (($decoded_2x_service ne $ticket->service_jstripped) || ($decoded_2x_service ne $ticket->service)) {
                # try for double url-encoded TARGET= parameters
                $self->app->log->warn("CasServer - saml_validate - 2x decode - ticket issued to " . 
                    $ticket->meritcommons_session->meritcommons_user->userid . " for service '@{[$ticket->service]}' " .
                    "does not match TARGET service '$decoded_2x_service'");
                
                # Ticket service does not match the one passed.  Per the spec, the ticket must be invalidated
                $service_response->add_authentication_failure("INVALID_SERVICE",
                    "Service specified does not match service associated with ticket");
            } else {
                # Ticket is valid
                $service_response->set_authenticated_user($ticket->meritcommons_session->meritcommons_user->userid);
                
                if ($service eq $ticket->service) {
                    $service_response->set_service($ticket->service);
                    $self->app->log->info("CasServer - ticket for service '$service' matched ticket service '@{[$ticket->service]}' " . 
                        "without any tweaks")
                } elsif ($service eq $ticket->service_jstripped) {
                    $service_response->set_service($ticket->service_jstripped);
                    $self->app->audit_log("CasServer - ticket for service '$service' matched ticket service '@{[$ticket->service]}' " .
                        "after stripping the jsessionid info");
                } else {
                    # this didn't match what we have in the ticket, most likely because of it's url encoded /'s
                    $service_response->set_service($service);
                    $self->app->audit_log("CasServer - ticket for service '$service' matched ticket service '@{[$ticket->service]}' " .
                        "only after urldecoding the value passed in TARGET twice, passing through TARGET verbatim.");
                }
                                
                $service_response->set_saml_assertion_expiration($self->casserver->plugin_config->{saml_assertion_expiration});
                $service_response->set_saml_not_before_skew($self->casserver->plugin_config->{saml_not_before_skew});

                # MeritCommons sessions persist and allow new CAS tickets without reauthentication, so this attribute should be true
                $service_response->add_attribute('longTermAuthenticationRequestTokenUsed','true');
                
                $self->app->emit('cas_before_authenticated_response', 
                        $self,
                        $service_response, 
                        $ticket->meritcommons_session->meritcommons_user, 
                        $ticket->meritcommons_session
                );

                if ($self->stash('further_auth_required')) {
                    $self->app->audit_log("CasServer::saml_validate - ticket for @{[$ticket->meritcommons_session->meritcommons_user->userid]} did not " . 
                        "have a session that satisfied the 2FA requirement for its role set.  returning INVALID_REQUEST");
                    
                    $service_response->add_authentication_failure("INVALID_REQUEST", "Ticket " . $ticket_id . "'s backing " .
                        "session did not satisfy all authentication requirements");
                    $ticket->consumed(1);
                    $ticket->update();
                } else {
                    $self->app->log->info("CasServer - ticket for service '@{[$ticket->service]}' issued at @{[scalar $ticket->issue_time]} " . 
                        "has been successfully consumed");
                }
            }

            $ticket->consumed(1);
            $ticket->update;    # tickets are only valid for one validation
        
        } else {
            $service_response->add_authentication_failure("INVALID_TICKET", "Ticket " . $ticket_id . " not recognized");
        }
    }

    my $xml = $service_response->to_string();

    if (($self->casserver->plugin_config->{debug}) && ($self->casserver->plugin_config->{debug} == 1)) { 
        print $xml . "\n";
    }

    $self->render(text => $xml, format => 'xml');
}

sub service_validate {
    my ($self) = @_;

    my $service   = $self->param('service');
    my $ticket_id = $self->param('ticket');
    my $renew     = ($self->param('renew')) ? 1 : 0;
    my $pgt_url   = $self->param('pgtUrl');

    my $xml = $self->_service_proxy_validate(0, $service, $ticket_id, $renew, $pgt_url);
    $self->render(text => $xml, format => 'xml');
}

sub proxy_validate {
    my ($self) = @_;

    my $service   = $self->param('service');
    my $ticket_id = $self->param('ticket');
    my $renew     = ($self->param('renew')) ? 1 : 0;
    my $pgt_url   = $self->param('pgtUrl');

    my $xml = $self->_service_proxy_validate(1, $service, $ticket_id, $renew, $pgt_url);
    $self->render(text => $xml, format => 'xml');
}

sub _service_proxy_validate {
    my ($self, $include_proxy, $service, $ticket_id, $renew, $pgt_url) = @_;

    my $type = $include_proxy ? PROXY_VALIDATE_TYPE : SERVICE_VALIDATE_TYPE;
    my $service_response = MeritCommons::Plugin::CasServer::ServiceResponse->new($type);

    # Validate that all of the required parameters have been defined
    if (!$service || !$ticket_id) {
        $service_response->add_authentication_failure("INVALID_REQUEST",
            "Not all of the required request parameters were present");
    } elsif (($include_proxy) && !($ticket_id =~ /^(ST|PT)-/)) {
        $service_response->add_authentication_failure("INVALID_TICKET", "Invalid ticket type for method");
    } elsif ((!$include_proxy) && !($ticket_id =~ /^(ST)-/)) {
        $service_response->add_authentication_failure("INVALID_TICKET", "Invalid ticket type for method");
    } else {

        # Attempt to locate the ticket
        my $ticket = $self->app->m->resultset('MeritCommons::Plugin::CasServer::Model::Ticket')->search(
            {
                ticket_id => $ticket_id,
                consumed  => 0
            }
        )->first;

        if ($ticket) {
            if (time > ($ticket->issue_time + $self->casserver->plugin_config->{ticket_expiration})) {

                # Ticket has expired
                $service_response->add_authentication_failure("INVALID_TICKET", "Ticket has expired");
            } elsif (($renew == 1) && ($ticket->renew != 1)) {
                $service_response->add_authentication_failure("INVALID_TICKET",
                    "Ticket must be generated through a direct login, not SSO");

            } elsif ($self->strip_jsession($ticket->service) ne $self->strip_jsession($service)) {

                # Ticket service does not match the one passed.  Per the spec, the ticket must be invalidated
                $service_response->add_authentication_failure("INVALID_SERVICE",
                    "Service specified does not match service associated with ticket");
            } else {

                # Create PGT tickets if a PGT URL was specified
                if ($pgt_url) {
                    my $pgtiou_ticket =
                      $self->casserver->create_ticket("PGTIOU", $ticket->service,
                        $ticket->issue_time, $ticket->renew, $pgt_url, $ticket->id, 0);
                    my $pgt_ticket =
                      $self->casserver->create_ticket("PGT", $ticket->service,
                        $ticket->issue_time, $ticket->renew, $pgt_url, $ticket->id, 0);

                    # Send the pgtIou and pgtId to the backend service
                    my $ua = Mojo::UserAgent->new;

                    # Validate SSL certs in non-dev environments
                    if ($self->app->mode ne "development") {
                        $ua = $ua->ca($self->casserver->plugin_config->{ca_file});
                    }

                    my $tx = $ua->get(
                        $pgt_url => form => {
                            pgtIou => $pgtiou_ticket->ticket_id,
                            pgtId  => $pgt_ticket->ticket_id
                        }
                    );

                    # Add the service response if the PGT URL returned a 200
                    if ($tx->res->code && ($tx->res->code == 200)) {
                        $service_response->add_proxy_granting_ticket($pgtiou_ticket->ticket_id);
                    }
                }

                # Ticket is valid
                $service_response->add_authentication_success($ticket->meritcommons_session->meritcommons_user->userid);
                $service_response->set_service($service);

                $self->app->emit('cas_before_authenticated_response', 
                    $self, 
                    $service_response, 
                    $ticket->meritcommons_session->meritcommons_user, 
                    $ticket->meritcommons_session,
                );

                if ($self->stash('further_auth_required')) {
                    $self->app->log->error("CasServer::saml_validate - ticket for @{[$ticket->meritcommons_session->meritcommons_user->userid]} did not " . 
                        "have a session that satisfied the 2FA requirement for its role set.  returning INVALID_REQUEST");
                    
                    $service_response->add_authentication_failure("INVALID_REQUEST", "Ticket " . $ticket_id . "'s backing " .
                        "session did not satisfy all authentication requirements");
                    $ticket->consumed(1);
                    $ticket->update();
                }
                        
                # Traverse through the proxy chain and record the URLs
                my @proxies;
                my $child_ticket = $ticket;
                while (
                    $child_ticket->issued_by_ticket
                    && (
                        my $parent_ticket =
                        $self->app->m->resultset('MeritCommons::Plugin::CasServer::Model::Ticket')->search(
                            {
                                id => $child_ticket->issued_by_ticket->id
                            }
                        )->first
                    )
                  ) {

                    if ($parent_ticket->pgt_url) {
                        push(@proxies, $parent_ticket->pgt_url);
                    }

                    $child_ticket = $parent_ticket;
                }

                if (scalar(@proxies) > 0) {
                    $service_response->proxies(\@proxies);
                }
            }

            $ticket->consumed(1);
            $ticket->update;    # tickets are only valid for one validation
        } else {
            $service_response->add_authentication_failure("INVALID_TICKET", "Ticket " . $ticket_id . " not recognized");
        }
    }

    return $service_response->to_string();
}

sub proxy {
    my ($self) = @_;

    my $target_service = $self->param('targetService');
    my $pgt            = $self->param('pgt');

    my $service_response = MeritCommons::Plugin::CasServer::ServiceResponse->new(PROXY_TYPE);

    if (!$target_service || !$pgt) {
        $service_response->add_proxy_failure("INVALID_REQUEST",
            "'pgt' and 'targetService' parameters are both required");
    } elsif (!($pgt =~ /^PGT-/)) {
        $service_response->add_proxy_failure("BAD_PGT", "Invalid proxy granting ticket");
    } else {

        # Attempt to locate the ticket
        my $pgt_ticket = $self->app->m->resultset('MeritCommons::Plugin::CasServer::Model::Ticket')->search(
            {
                ticket_id => $pgt,
                consumed  => 0
            }
        )->first;

        if ($pgt_ticket) {
            my $pt_ticket = $self->casserver->create_ticket("PT", $pgt_ticket->meritcommons_session->meritcommons_user,
                $target_service, $pgt_ticket->issue_time, $pgt_ticket->renew, undef, $pgt_ticket->id, 0);
            $service_response->add_proxy_success($pt_ticket->ticket_id);
            $pgt_ticket->update;
        } else {
            $service_response->add_proxy_failure("BAD_PGT", "Proxy granting ticket could not be found");
        }
    }

    $self->render(text => $service_response->to_string(), format => 'xml');
}

1;
