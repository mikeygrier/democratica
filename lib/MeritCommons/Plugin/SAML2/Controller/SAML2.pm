package MeritCommons::Plugin::SAML2::Controller::SAML2;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw/trim b64_encode b64_decode url_escape/;
use Mojo::URL;
use Mojo::DOM;
use Mojo::File;
use Time::HiRes;

sub metadata {
    my ($self) = @_;

    my $md_file = "@{[$self->saml2->plugin->plugin_data_dir]}/metadata.xml";
    unless (-e $md_file) {
        $self->saml2->render_metadata;
    }

    # return the XML!
    $self->render(data => Mojo::File->new($md_file)->slurp, format => 'xml');
}

sub logout {
    my ($self) = @_;

    my $request = b64_decode($self->param('SAMLRequest'));
    if ($request) {
        my $doc = Mojo::DOM->new()->xml(1)->parse($request);
        my $issuer = $doc->at('Issuer')->text;
        
        # assumed federation agreement
        my $afa = $self->saml2->federation($issuer);
        
        # determine true federation agreement and true entity id.
        my ($federation, $entity_id);
        if (ref $afa eq "HASH" && $afa->{authn_requests_signed}) {
            my $rv = $self->saml2->verify_signed_xml({
                xml_document => $doc,
                validate_signature_and_issuer => 1,
                allow_unsigned => 0, 
            });
            if ($rv) {
                if ($rv eq $issuer) {
                    # the assumed federation agreement has been authenticated as the federation agreement.
                    $federation = $afa;
                    
                    # the issuer has proven to be the entity_id by its signature.
                    $entity_id = $rv;
                }
            }
        }
        
        # since LogoutRequests don't technically have to be signed, we should parse it unsigned, too.
        unless ($federation && $entity_id) {
            my $rv = $self->saml2->verify_signed_xml({
                xml_document => $doc,
                validate_signature_and_issuer => 1,
                allow_unsigned => 1, 
            });
            
            if ($rv ne $issuer && $rv =~ /^(\Q$issuer\E);/) {
                $rv = $1;
                $self->app->log->warn("SAML2 Logout - Unsigned LogoutRequest received from $issuer");
            }
            
            # good 'nuff
            if (ref $afa eq "HASH" && $rv eq $issuer) {
                $federation = $afa;
                $entity_id = $rv;  
            } 
        }

        # pull out the essentials...
        my $name_id = $doc->at('NameID')->text;
        my $request_id = $doc->at('LogoutRequest')->attr('ID');
        my ($req_session_id, $session_id);
        eval { $req_session_id = $doc->at('SessionIndex')->text; };
        eval { $session_id = $self->meritcommons_session->session_id; };
        
        if ($federation && ref($federation) eq "HASH" && $federation->{assertion_consumer_url}->[0]) {
            $self->stash(
                destination_url => $federation->{assertion_consumer_url}->[0],
                assertion_consumer_url => $federation->{assertion_consumer_url}->[0],
                response_id => "_@{[$self->new_uuid]}",
                in_response_to => $request_id,
                issue_instant => $self->saml2->timestamp,
                wreply => ($self->saml2->config->{logout_to_auth_url} && $self->app->config->{auth_url}) ? $self->app->config->{auth_url} : '',
            );
            if ($federation->{entity_id} eq $issuer) {
                if (($req_session_id eq $session_id) || ($session_id && !$req_session_id)) {
                    if (my $session = $self->meritcommons_session($session_id)) {
                        if ($session->is_expired) {
                            $self->stash(status_message => "User session expired; Logout not required");
                            $self->stash(status_code => "urn:oasis:names:tc:SAML:2.0:status:Success");
                        } else {
                            # Session active
                            if ($self->saml2->config->{logout_destroys_meritcommons_session} || $federation->{logout_destroys_meritcommons_session}) {
                                $self->destroy_session;
                                $self->stash(status_message => "Master portal session also cleared");
                                $self->stash(status_code => "urn:oasis:names:tc:SAML:2.0:status:Success");
                            } else {
                                $self->stash(status_message => "Due to system configuration, master portal session was not cleared");
                                $self->stash(status_code => "urn:oasis:names:tc:SAML:2.0:status:PartialLogout");
                            }
                        }
                    } else {
                        $self->stash(status_message => "User session not found; Logout not possible");
                        $self->stash(status_code => "urn:oasis:names:tc:SAML:2.0:status:Success");
                    }
                } else {
                    $self->stash(status_message => "SessionIndex supplied in assertion does not match the current session_id");
                    $self->stash(status_code => "urn:oasis:names:tc:SAML:2.0:status:RequestDenied")
                }
            } else {
                $self->stash(status_message => "Issuer did not match entityId of key used in signature");
                $self->stash(status_code => "urn:oasis:names:tc:SAML:2.0:status:RequestDenied");
            }

            if ($doc->at('Extensions > Asynchronous')) {                    
                if (my $al_url = $federation->{after_logout_url}) {
                    my $url;
                    if (my $auth_url = $self->app->config->{auth_url}) {
                        $url = Mojo::URL->new($auth_url);

                        # merge all the details into the logout url
                        my $to_merge = [
                            $self->app->config->{auth_back_param} => $al_url,
                        ];
                        
                        my $lp = $self->saml2->config->{logout_parameters};
                        if (ref $lp eq "HASH") {
                            foreach my $key (keys %$lp) {
                                push(@$to_merge, $key, $lp->{$key});
                            }
                        }

                        # merge these values in
                        $url->query($to_merge);
                    } else {
                        # we'll just send them to the after logout url
                        $url = Mojo::URL->new($al_url);
                    }
                } else {
                    $self->render(
                        template => 'general/message',
                        title => "Logout Successful", 
                        message => "You have been successfully logged out of the external application",
                    );
                }
            } else {
                $self->stash(saml_response => b64_encode($self->render_to_string(template => 'saml2_logout_response', format => 'xml'), ''));                
                $self->render(template => 'saml2_http_post_response');
            }
        } else {
            $self->render(text => "Federation Agreement not found, or LogoutRequest not signed");
        }
    } else {
        $self->render(text => 'No SAMLRequest found');
    }
}

sub test_authn_request {
    my ($self) = @_;

    my $request_id = $self->new_uuid;
    $self->stash(
        request_id => $request_id,
        force_authn => 'false',
        not_before => $self->saml2->timestamp, # now
        issue_instant => $self->saml2->timestamp, # also now
    );

    if ($self->param('format') eq "URL") {
        my $ar_string;
        eval {
            $ar_string = b64_encode($self->saml2->deflate($self->render_to_string(template => 'saml2_authn_request', format => 'xml')), '');
        };
        $self->render(text => "http://meritcommons-dev.wayne.edu:3000/saml2/http_redirect?SAMLRequest=@{[url_escape $ar_string]}");
    } else {
        $self->render(template => 'saml2_authn_request', format => 'xml');
    }
}

sub sp_initiated_sso {
    my ($self) = @_;

    if ($self->stash->{asserted_to_entity_id}) {
        $self->res->headers->add('X-Misbehaving-SAML2-SP' => 1);
    }

    my ($authn_request, $relay_state, $binding_used);
    if (my $ar_id = $self->param('authn_request_id')) {
        my $car = $self->cache->get("saml2-$ar_id");
        if (ref $car eq "HASH") {
            $authn_request = $car->{authn_request};
            $relay_state = $car->{relay_state};
            $binding_used = $car->{binding_used};
        }
    } else {
        # this is initial contact, not a pull from cache.  make sure the methods line up with the
        # madness.
        if (($self->stash->{http_redirect_binding} && $self->tx->req->method eq "GET") ||
            ($self->stash->{http_post_binding} && $self->tx->req->method eq "POST")) {
            $authn_request = $self->param('SAMLRequest');
            $relay_state = $self->param('RelayState');
            $binding_used = $self->stash->{http_redirect_binding}   ? 'http_redirect_binding'   : 
                            $self->stash->{http_post_binding}       ? 'http_post_binding'       : 'unknown';
                            
            if ($binding_used eq "unknown") {
                $self->fatal_error("SAML2 Error", "sp_initiated_sso attempting to use an unknown binding");
                $self->audit_log("Bogus Request: " . $authn_request);
            }
        } else {
            $self->fatal_error("SAML2 Error", "method used doesn't match binding endpoint expected behavior");
        }
    }

    if ($authn_request) {
        my ($ar, $request_id, $issuer);
        eval {
            # since this could be cached for a recent login, or just presented to us, we have to rely
            # on the binding detected above or pulled from cache to determine how to handle the data
            my $ar_xml;
            if ($binding_used eq "http_redirect_binding") {
                $ar_xml = $self->saml2->inflate(b64_decode($authn_request));
            } else { 
                # assumed HTTP-POST, but won't try and inflate in any case.
                $ar_xml = b64_decode($authn_request);
            }
            $ar = Mojo::DOM->new->xml(1)->parse($ar_xml);
            $request_id = $ar->at('AuthnRequest')->attr('ID');
            $issuer = $ar->at('Issuer')->text;
        };

        if (my $error = $@) {
            $self->fatal_error("SAML2 Error", "SAML2 AuthnRequest Parse Error", "exception thrown while parsing XML '$error': $authn_request $ar $issuer)");
        } else {
            # turn ForceAuthn into 1 if "true" 0 if not present or false.
            my $force_authn = $ar->at('AuthnRequest')->attr('ForceAuthn');
            if ($force_authn && $force_authn eq "true") {
                # allow plugins to have a say on the enforcement of ForceAuthn per issuer, yes i know. i know.. 
                # but there's some REALLY bad software out there.
                $self->stash('force_authn', 1);
                $self->app->emit('saml2_authn_request_pre_force_authn', $issuer);
                $force_authn = $self->stash('force_authn');
            } else {
                $force_authn = 0;
            }
            
            #
            # Conditions for AuthN Response via HTTP POST
            # User is logged in and ForceAuthn was not "true" in the AuthnRequest
            # User is logged in with a session created in the last 10 seconds and ForceAuthn was "true" in the AuthnRequest
            #
            if ((my $user = $self->active_user) && ($self->meritcommons_session->create_time > (time - 10) || !$force_authn)) {
                # already authenticated!
                if (my $error = $@) {
                    $self->fatal_error("SAML2 Parse Error", $error);
                } else {
                    if (my $entity_id = $self->saml2->verify_signed_xml($ar, 0, 1)) {
                        # permit them to use arbitrary AssertionConsumerServiceURLs with unsigned requests, i guess this is a thing?
                        if (my $alt_ac_url = $ar->at('AuthnRequest')->attr('AssertionConsumerServiceURL')) {
                            $self->stash(assertion_consumer_url => $alt_ac_url);
                        }
            
                        if ($entity_id =~ /^\Q$issuer/) {
                            $self->stash(in_response_to => $request_id, relay_state => $relay_state);
                            $self->saml2->post_response_to($issuer);
                        } else {
                            $self->fatal_error("SAML2 Error", "unknown federation agreement for '$issuer', $entity_id");
                        }
                    } else {
                        $self->fatal_error("SAML2 Error", "signature not verified, or entity not found for entity '$entity_id'");       
                    }
                }
            } else {
                if ($force_authn && $self->active_user) {
                    $self->app->log->error("ForceAuthn set to true in AuthnRequest ID $request_id from $issuer, killing session and prompting for login!");
                } else {
                    $self->app->log->error("SAML2 federation error: No MeritCommons session found, prompting for login!");
                }
                if ($self->req->method eq "POST") {
                    # cache for 120 seconds.  must come back soon.
                    $self->cache->set("saml2-$request_id", { 
                        authn_request => $authn_request, 
                        relay_state => $relay_state,
                        binding_used => $binding_used,
                    }, 120);
                    
                    $self->auth_log("SAML2 with $binding_used used requires (re)authentication - passing user through auth flow");
                    
                    my $back_url = $self->req->url;
                    $back_url->query([authn_request_id => $request_id]);
                    if ($relay_state) {
                        $back_url->query([RelayState => $relay_state]);
                    }

                    $self->redirect_to('/auth?logout=1&back=' . 
                        url_escape("/login?heading_title=Session+Expired&message=Please+confirm+your+identity&back=" .
                            url_escape($back_url->to_string)
                        )
                    )
                } else {
                    $self->redirect_to("/auth?logout=1&back=" . 
                        url_escape("/login?heading_title=Session+Expired&message=Please+confirm+your+identity&back=@{[url_escape($self->req->url->to_string)]}")
                    );
                }
            }
        }
    } else {
        $self->fatal_error("SAML2 Parse Error", "SAMLRequest not found");
    }
}

sub artifact_resolution {
    my ($self) = @_;

    $self->app->log->error("Hi, Artifact Resolution got called!");
    $self->app->log->error($self->req->to_string);
    $self->render(text => "Hello");
}

sub idp_initiated_sso {
    my ($self) = @_;

    if (my $user = $self->active_user) {
        my $entity_id = $self->param('entity_id') // $self->stash('entity_id');
        $self->stash(in_response_to => '');
        $self->saml2->post_response_to($entity_id);
    } else {
        $self->app->log->error("SAML2 federation error: No MeritCommons session found, prompting for login!");
        $self->redirect_to("/auth?logout=1&back=" . 
            url_escape("/login?heading_title=Session+Expired&message=Please+confirm+your+identity&back=@{[url_escape($self->req->url->to_string)]}")
        );
    }
}

1;