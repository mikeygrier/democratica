package MeritCommons::Plugin::OAuth2::Controller::Endpoints;

use MIME::Base64 qw/encode_base64 decode_base64/;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::URL;

# we already have this in memory but we need to chop it up to serve it.
sub rsa_pubkey {
    my ($c) = @_;

    $c->render(text => $c->oauth2->x509_pem);
}

sub callback {
    my ($c) = @_;
    $c->render(text => '<pre>' . $c->tx->req->to_string . "</pre>");
}

sub verify_token {
    my ($c) = @_;

    my $token = $c->param('access_token');

    if ($token) {
        $c->render(text => '<pre>Result: ' . $c->dumper($c->oauth2->verify_jwt($token)) . '</pre>');
    }
}

sub access_token {
    my ($c) = @_;

    my $grant_type = $c->param('grant_type');
    my $code = $c->param('code');
    my $redirect_uri = $c->param('redirect_uri');
    my $state = $c->param('state');

    my ($client_id, $client_secret); 

    # look for them in params if this is a post.
    if ($c->req->method eq "POST") {
        $client_id = $c->param('client_id');
        $client_secret = $c->param('client_secret');
    }

    # or look for them in an authorization header (trumps params)
    if (my $http_auth = $c->req->headers->authorization) {
        if ($http_auth =~ /^Basic (.+)$/) {
            ($client_id, $client_secret) = split(/:/, decode_base64($1));
        }
    }

    unless ($client_id && $client_secret) {
        $c->res->headers->www_authenticate("Basic realm=OAuth2 Access Token Retrieval");
        $c->res->code(401);
        $c->rendered;
        return;
    }

    # now let's get the client.
    if (my $client = $c->oauth2->client($client_id)) {
        # and make sure the secret matches.
        if ($client->authenticate($client_secret)) {
            # client's good, determine if we're responding to an authorization request or if we're doing a
            # credential authentication...
            if ($grant_type eq "credentials") {
                if ($c->req->method eq "POST") {
                    my $username = $c->param('username');
                    my $password = $c->param('password');
                    my $scope = $c->every_param('scope');

                    if (my $user = $c->authenticate_user($username, $password)) {                
                        my $access_token = {
                            aud => $scope,
                            exp => time + $c->oauth2->plugin_config->{access_token_validity_duration},
                            sub => $user->userid,
                            _client_unique_id => $client->unique_id,
                            _password => $password,
                        };

                        my $refresh_token = {
                            %$access_token,
                            exp => time + $c->oauth2->plugin_config->{refresh_token_validity_duration},
                            _refresh_token => 1,
                        };

                        $c->render(json => {
                            token_type => 'bearer',
                            expires_in => $c->oauth2->plugin_config->{access_token_validity_duration},
                            refresh_expires_in => $c->oauth2->plugin_config->{refresh_token_validity_duration},
                            access_token => $c->oauth2->generate_jwt($access_token),
                            refresh_token => $c->oauth2->generate_jwt($refresh_token),
                        });
                    } else {
                        if ($redirect_uri) {
                            my $url = Mojo::URL->new($redirect_uri);
                            $url->query->merge(state => $state, error => 'invalid_request', error_description => 'invalid user login credentials');
                            $c->redirect_to($url->to_abs);
                        } else {
                            $c->render(text => 'invalid_request');
                        }
                    }
                } else {
                    if ($redirect_uri) {
                        my $url = Mojo::URL->new($redirect_uri);
                        $url->query->merge(state => $state, error => 'invalid_request', error_description => 'unsupported HTTP method');
                        $c->redirect_to($url->to_abs);
                    } else {
                        $c->render(text => 'invalid_request');
                    }
                }
            } else {
                my $auth_info = $c->cache->get($code) if $code;
                if ($auth_info) {
                    if ($auth_info->{redirect_uri} eq $redirect_uri) {
                        my $at_duration = $c->oauth2->plugin_config->{access_token_validity_duration};
                        my $rt_duration = $c->oauth2->plugin_config->{refresh_token_validity_duration};

                        my $access_token = {
                            aud => [split(/\s+/, $auth_info->{scope})],
                            exp => time + $at_duration,
                            sub => $auth_info->{user},
                            _client_unique_id => $client->unique_id,
                        };

                        if (my $pw = $c->decrypt_cookie_payload($auth_info->{_cookie})) {
                            $access_token->{_password} = $pw;
                        }

                        # refresh token is just a copy with a different expiration
                        my $refresh_token = {
                            %$access_token,
                            exp => time + $rt_duration,
                            _refresh_token => 1,
                        };

                        $c->cache->delete($code);

                        $c->render(json => {
                            token_type => 'bearer',
                            expires_in => $at_duration,
                            refresh_expires_in => $c->oauth2->plugin_config->{refresh_token_validity_duration},
                            access_token => $c->oauth2->generate_jwt($access_token),
                            refresh_token => $c->oauth2->generate_jwt($refresh_token),
                        });

                    } else {
                        if ($redirect_uri) {
                            my $url = Mojo::URL->new($redirect_uri);
                            $url->query->merge(state => $state, error => 'invalid_request', error_description => 'redirect_uri mismatch');
                            $c->redirect_to($url->to_abs);
                        } else {
                            $c->render(text => 'invalid_request');
                        }
                    }
                } elsif (my $refresh_token = $c->param('refresh_token')) {
                    if ($c->req->method eq "POST") {
                        my $rft = $c->oauth2->verify_jwt($refresh_token);
                        if (ref($rft) eq "HASH" && $rft->{_is_refresh_token}) {
                            # get the token DB record.
                            my $rft_rec = $c->oauth2->token($rft->{jti});
                            if ($rft_rec) {
                                # clean out the internal stuff from the old token
                                foreach my $k (qw/jti _is_refresh_token _verification_algorithm _verified_from_client/) {
                                    delete $rft->{$k};
                                }

                                # grab the password and transfer it over with a new password
                                my $ap_cred = delete $rft->{ap_cred};
                                if (my $key = $rft_rec->auxiliary_secret) {
                                    $rft->{_password} = $c->decrypt_pw($ap_cred, $key, $rft_rec->id);
                                }
                                
                                if (!$rft->{_password} || $c->authenticate_user($rft->{userid}, $rft->{_password})) {
                                    $rft_rec->number_issued($rft_rec->number_issued + 1);
                                    $rft_rec->update;

                                    # only thing really changing will be the expire time
                                    $rft->{exp} = time + $c->oauth2->plugin_config->{access_token_validity_duration};
                                    $rft->{_client_unique_id} = $rft_rec->client->unique_id;

                                    $c->render(json => {
                                        token_type => 'bearer',
                                        expires_in => $c->oauth2->plugin_config->{access_token_validity_duration},
                                        refresh_expires_in => ($rft_rec->expire_time - time),
                                        access_token => $c->oauth2->generate_jwt($rft),
                                    });
                                } else {
                                    if ($redirect_uri) {
                                        my ($url) = Mojo::URL->new($redirect_uri);
                                        $url->query->merge(state => $state, error => 'invalid_token', error_description => 'invalid or expired refresh token');
                                        $c->redirect_to($url->to_abs);
                                    } else {
                                        $c->render(text => 'invalid_token');
                                    }
                                }
                            } else {
                                if ($redirect_uri) {
                                    my $url = Mojo::URL->new($redirect_uri);
                                    $url->query->merge(state => $state, error => 'invalid_token', error_description => 'invalid or expired refresh token');
                                    $c->redirect_to($url->to_abs);
                                } else {
                                    $c->render(text => 'invalid_token');
                                }
                            }
                        } else {
                            if ($redirect_uri) {
                                my $url = Mojo::URL->new($redirect_uri);
                                $url->query->merge(state => $state, error => 'invalid_token', error_description => 'invalid or expired refresh token');
                                $c->redirect_to($url->to_abs);
                            } else {
                                $c->render(text => 'invalid_token');
                            }
                        }
                    } else {
                        if ($redirect_uri) {
                            my $url = Mojo::URL->new($redirect_uri);
                            $url->query->merge(state => $state, error => 'invalid_request', error_description => 'unsupported HTTP method');
                            $c->redirect_to($url->to_abs);
                        } else {
                            $c->render(text => 'invalid_request');
                        }
                    }
                } else {
                    if ($redirect_uri) {
                        my $url = Mojo::URL->new($redirect_uri);
                        $url->query->merge(state => $state, error => 'invalid_grant', error_description => 'invalid or expired authorization code');
                        $c->redirect_to($url->to_abs);
                    } else {
                        $c->render(text => 'invalid_grant');
                    }
                }
            }
        } else {
            if ($redirect_uri) {
                my $url = Mojo::URL->new($redirect_uri);
                $url->query->merge(state => $state, error => 'unauthorized_client', error_description => 'invalid client login credentials');
                $c->redirect_to($url->to_abs);
            } else {
                $c->render(text => 'unauthorized_client');
            }
        }
    } else { 
        if ($redirect_uri) {
            my $url = Mojo::URL->new($redirect_uri);
            $url->query->merge(state => $state, error => 'unauthorized_client');
            $c->redirect_to($url->to_abs);
        } else {
            $c->render(text => 'unauthorized_client');
        }
    }
    
}

sub authorization_grant {
    my ($c) = @_;

    my $client_id = $c->param('client_id');
    my $redirect_uri = $c->param('redirect_uri') // $c->param('destination_url');
    my $response_type = $c->param('response_type');
    my $scope = $c->param('scope');
    my $state = $c->param('state');

    # first make sure we have a registered client
    if (my $client = $c->oauth2->client($client_id)) {

        $redirect_uri //= $client->callback_url;
        my $url = Mojo::URL->new($redirect_uri);

        # do a quick state check
        if ($c->cache->get($c->sha256_hex($client->unique_id . $state . $c->tx->remote_address)) eq $state) {
            my $username = $c->param('username');
            my $password = $c->param('password');
            my $user;
            if ($user = $c->active_user) {
                $c->auth_log("@{[$user->userid]} - OAuth2 user already has valid MeritCommons session; Serving client '@{[$client->common_name]}'");
            } else {
                if (my $session = $c->new_session("oauth2_authz_request", $username, $password)) {
                    $user = $session->meritcommons_user;

                    # other stuff might need this..
                    $c->stash(active_user => $user);

                    $c->auth_log("@{[$user->userid]} - OAuth2 user authenticated successfully; Serving client '@{[$client->common_name]}'");
                }
            }

            if ($user) {
                # this is for double checking that they dont change around the redirect URL on us
                my $code = $c->random_b64u(64);

                my $cookie_value;
                if (my $cookie = $c->tx->req->cookie('wayneAuth')) {
                    $cookie_value = $cookie->value;
                } elsif ($cookie = $c->tx->res->cookie('wayneAuth')) {
                    $cookie_value = $cookie->value;
                }

                $c->cache->set($code, {
                    client => $client->unique_id,
                    redirect_uri => $url->to_abs,
                    user => $user->unique_id,
                    scope => $scope,
                    state => $state,
                    _cookie => $cookie_value,
                }, 300);

                $c->render(
                    template => 'oauth2/summarize_and_confirm',
                    scope => [map { $c->oauth2->scope($_) // $_ } split(/\s+/, $scope)],
                    code => $code,
                    state => $state,
                    redirect_uri => $redirect_uri,
                    client => $client,
                );
            } else {
                if (my $auth_url = $c->global_config->{auth_url}) {
                    my $url = Mojo::URL->new($auth_url);
                    
                    # after login via auth_url come back here with all this info
                    my $destination_url = $c->req->url->clone;
                    $destination_url->query([
                        redirect_uri => $redirect_uri,
                        client => $client,
                        scope => $scope,
                        state => $state,
                    ]);
                    
                    # merge in any special attributes required to clear session along with a way back here once we've authenticated
                    my $to_merge = [
                        destination_url => $destination_url->to_string,
                    ];                    
                    my $lp = $c->oauth2->plugin_config->{logout_parameters};
                    
                    if (ref $lp eq "HASH") {
                        foreach my $key (keys %$lp) {
                            push(@$to_merge, $key, $lp->{$key});
                        }
                    }
                    
                    $url->query($to_merge);
                    $c->redirect_to($url);
                } else {
                    $c->render(
                        template => 'oauth2/login', 
                        scope => $scope, 
                        state => $state, 
                        response_type => $response_type, 
                        redirect_uri => $redirect_uri,
                        message => "Please Authenticate",
                    );
                }
            }
        } else {
            $url->query->merge(error => 'invalid_request', error_description => 'state mismatch');
            $c->redirect_to($url->to_abs);
        }
    } else {
        if ($redirect_uri) {
            my $url = Mojo::URL->new($redirect_uri);
            $url->query->merge(state => $state, error => 'unauthorized_client');
            $c->redirect_to($url->to_abs);
        } else {
            $c->render(text => 'unauthorized_client');
        }
    }
}

# convert an enhanced OAuth2 token to an meritcommons wayneauth 3 session
sub oauth2_to_meritcommons {
    my ($self) = @_;
    
    my $back = $self->param('back') // $self->param('destination_url') // '/';
    
    my $t = $self->param('access_token');
    unless ($t) {
        ($t) = $self->req->headers->authorization =~ /^Bearer ([\w\.\-]+)/;
    }
    
    if ($t) {
        if (my $vt = $self->oauth2->verify_jwt($t)) {
            if (ref $vt eq "HASH") {
                if (my $ap_cred = $vt->{ap_cred}) {
                    if (my $token = $self->oauth2->token($vt->{jti})) {
                        my $pw = $self->decrypt_pw($ap_cred, $token->auxiliary_secret, $token->id);
                        if ($vt->{userid} && $pw && $self->authenticate_user($vt->{userid}, $pw)) {
                            
                            my @session;
                            if (my $user = $self->active_user) {
                                if (lc($user->userid) eq lc($vt->{userid})) {
                                    $session[0] = $self->meritcommons_session;
                                }
                            }

                            unless ($session[0]) {
                                @session = $self->new_session("oauth2_conversion", $vt->{userid}, $pw);
                            } 

                            if ($session[0]) {
                                $self->auth_log("$vt->{userid} - OAuth2 to MeritCommons conversion successful");
                                if ($back) {
                                    $self->redirect_to($back);
                                } else {
                                    $self->render(text => "success");
                                }
                            } else {
                                $self->auth_log("$vt->{userid} - OAuth2 to MeritCommons conversion FAILED - password changed");
                                if ($back) {
                                    $self->redirect_to($back);
                                } else {
                                    $self->render(text => "[error] valid token; but users' credentials have changed");
                                }
                            }
                        } else {
                            $self->auth_log("$vt->{userid} - OAuth2 to MeritCommons conversion FAILED - credentials expired");
                            $self->render(text => "[error] valid token; but credentials expired");                        
                        }
                    } else {
                        $self->auth_log("$vt->{userid} - OAuth2 to MeritCommons conversion FAILED - not in database");
                        $self->render(text => "[error] valid token; but no record found in database");   
                    }
                } else {
                    $self->auth_log("$vt->{userid} - OAuth2 to MeritCommons conversion FAILED - absent ap_cred property");
                    $self->render(text => "[error] valid token; but lacking 'ap_cred' property");
                }
            } else {
                $self->auth_log("OAuth2 to MeritCommons conversion FAILED - invalid token");
                $self->render(text => "[error] invalid token");   
            }
        } else {
            $self->auth_log("OAuth2 to MeritCommons conversion FAILED - invalid token");
            $self->render(text => "[error] invalid token");
        }
    } else {
        $self->render(text => '[error] access_token not specified');
    }
}

sub authorization_request {
    my ($c) = @_;

    my $client_id = $c->param('client_id');
    my $redirect_uri = $c->param('redirect_uri');
    my $response_type = $c->param('response_type');
    my $scope = $c->param('scope');
    my $state = $c->param('state');

    # first make sure we have a registered client
    if (my $client = $c->oauth2->client($client_id)) {
        # if we do, let's get this party started..
        $redirect_uri //= $client->callback_url;

        my $url = Mojo::URL->new($redirect_uri);
        if ($response_type ne "code") {
            $url->query->merge(state => $state, error => 'unsupported_response_type');
            $c->redirect_to($url->to_abs);
        } else {
            # only have to maintain state for a short time.
            $c->cache->set($c->sha256_hex($client->unique_id . $state . $c->tx->remote_address), $state, 300);

            if ($c->active_user) {
                # we are already authenticated.
                $c->redirect_to(Mojo::URL->new('/oauth2/authorization_grant')->query(
                    response_type => $response_type,
                    scope => $scope,
                    state => $state,
                    client_id => $client_id,
                    redirect_uri => $url->to_abs,
                )->to_abs);
            } else {
                if (my $auth_url = $c->global_config->{auth_url}) {
                    my $url = Mojo::URL->new($auth_url);
                    
                    # after login via auth_url come back here with all this info
                    my $destination_url = $c->req->url->clone;
                    $destination_url->query([
                        redirect_uri => $redirect_uri,
                        client => $client,
                        scope => $scope,
                        response_type => $response_type,
                        state => $state,
                    ]);
                    
                    # merge in any special attributes required to clear session along with a way back here once we've authenticated
                    my $to_merge = [
                        destination_url => $destination_url->to_string,
                    ];                    
                    my $lp = $c->oauth2->plugin_config->{logout_parameters};
                    
                    if (ref $lp eq "HASH") {
                        foreach my $key (keys %$lp) {
                            push(@$to_merge, $key, $lp->{$key});
                        }
                    }
                    
                    $url->query($to_merge);
                    $c->redirect_to($url);
                } else {
                    $c->render(
                        template => 'oauth2/login', 
                        scope => $scope, 
                        state => $state, 
                        response_type => $response_type, 
                        redirect_uri => $redirect_uri,
                        message => "Please Authenticate",
                    );
                }
            }
        }
    } else {
        if ($redirect_uri) {
            my $url = Mojo::URL->new($redirect_uri);
            $url->query->merge(state => $state, error => 'unauthorized_client');
            $c->redirect_to($url->to_abs);
        } else {
            $c->render(text => 'unauthorized_client');
        }
    }
}

1;