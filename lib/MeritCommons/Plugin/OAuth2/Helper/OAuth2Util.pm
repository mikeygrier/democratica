#
# Util class for OAuth2
#

package MeritCommons::Plugin::OAuth2::Helper::OAuth2Util;

# base class first.
use Mojo::Base 'MeritCommons::Plugin';

use Mojo::JSON qw/encode_json decode_json/;
use MIME::Base64 qw/encode_base64url decode_base64url/;
use Mojo::Util qw/b64_decode b64_encode/;
use Crypt::Mac::HMAC qw/hmac/;
use Crypt::Digest qw/digest_data digest_data_hex/;
use Crypt::X509;
use Crypt::PK::RSA;

my $crypto = {
    'RS256' => {
        sign => sub {
            my ($sk, $to_sign) = @_;
            return encode_base64url($sk->sign_message($to_sign, 'SHA256', 'v1.5'), '');
        },
        verify => sub {
            my ($pk, $sig, $to_verify) = @_;
            return $pk->verify_message(decode_base64url($sig), $to_verify, 'SHA256', 'v1.5');
        }
    },

    # ECDSA, sure why not?  $sk and $pk must be Crypt::PK::ECC objects
    'ES256' => {
        sign => sub {
            my ($sk, $to_sign) = @_;
            return encode_base64url($sk->sign($to_sign), '');
        },
        verify => sub {
            my ($pk, $sig, $to_verify) = @_;
            return $pk->verify(decode_base64url($sig), $to_verify);
        }
    },

    # uses the same shared secret to sign as to verify
    'HS256' => {
        sign => sub {
            my ($sk, $to_sign) = @_;
            return encode_base64url(hmac('SHA256', $sk, $to_sign));
        },
        verify => sub {
            my ($sk, $sig, $to_verify) = @_;
            if (hmac('SHA256', $sk, $to_verify) eq decode_base64url($sig)) {
                return 1;
            }
            return undef;
        }
    }
};

sub register {
    my ($self, $app) = @_;

    $self->SUPER::register($app);

    $app->helper('oauth2.client' => \&_client);
    $app->helper('oauth2.scope' => \&_scope);
    $app->helper('oauth2.token' => \&_token);
    $app->helper('oauth2.generate_jwt' => \&_generate_jwt);
    $app->helper('oauth2.verify_jwt' => \&_verify_jwt);
    $app->helper('oauth2.create_client' => \&_create_client);
    $app->helper('oauth2.remove_client' => \&_remove_client);
    $app->helper('oauth2.modify_client' => \&_modify_client);
    $app->helper('oauth2.create_scope' => \&_create_scope);
    $app->helper('oauth2.remove_scope' => \&_remove_scope);
    $app->helper('oauth2.modify_scope' => \&_modify_scope);
}

# create a jwt for a user
sub _generate_jwt {
    my ($c, $jwt) = @_;

    # taking jwt as an argument allows users to customize the tokens.
    $jwt = {} unless ref $jwt eq "HASH";

    my $json_serialization = delete $jwt->{_json_serialization};
    my $client = $c->oauth2->client(delete $jwt->{_client_unique_id});
    my $user = $c->user($jwt->{sub});

    my $header = encode_base64url(encode_json({
        alg => 'RS256',
        'x5t#S256' => $c->thumbprint(b64_decode($c->oauth2->x509_string)),
        x5u => $c->global_config->{front_door_url} . '/oauth2/rsa/pubkey.pem',
    }), '');

    $jwt = {
        aud => $c->global_config->{front_door_url} . '/oauth2/trust',
        sub => $user->unique_id,
        exp => time + $c->global_config->{session_length},
        nbf => time,
        iat => time,
        jti => $c->new_uuid,
        userid => $user->userid,
        cn => $user->common_name,
        roles => [map { $_->common_name } $user->roles],

        # let passed values override defaults
        %$jwt,

        # but don't let anything override the issuer
        iss => $c->global_config->{front_door_url} . '/oauth2/trust',
    };

    my $token = $c->m->resultset("MeritCommons::Plugin::OAuth2::Model::Token")->create({
        meritcommons_user => $user->id,
        client => $client->id,
        unique_id => $jwt->{jti},
        signer_thumbprint => $c->thumbprint(b64_decode($c->oauth2->x509_string)),
        expire_time => $jwt->{exp},
    });

    # do user specific stuff here.
    if (my $password = delete $jwt->{_password}) {
        # they supplied a password... make sure it's for this user.
        if ($c->authenticate_user($user->userid, $password)) {
            # this is this user's password, this must be the intention of the caller
            my $key = $c->crypto_stream_key;
            my $enc_pw = $c->encrypt_pw($password, $key, $token->id);

            # the key goes in the database
            $token->auxiliary_secret($key);
            
            # but the encrypted password only ever goes into the token
            $jwt->{ap_cred} = $enc_pw;
        }
    }

    if (my $refresh = delete $jwt->{_refresh_token}) {
        $token->is_refresh_token(1);
    }

    # update the token in the database if we changed anything..
    if ($token->is_changed) {
        $token->update;
    }

    my $payload = encode_base64url(encode_json($jwt));
    my $sig = $crypto->{$c->oauth2->plugin_config->{signature_method}}->{sign}->($c->oauth2->rsa_sk, "$header.$payload");

    if ($json_serialization) {
        return encode_json({
            header => [$header],
            payload => $payload,
            signature => [$sig],
        });
    } else {
        return "$header.$payload.$sig";
    }
}

sub _token {
    my ($c, $unique_id) = @_;

    return $c->m->resultset('MeritCommons::Plugin::OAuth2::Model::Token')->find({ unique_id => $unique_id });
}

sub _client {
    my ($c, $search_string) = @_;

    my $client;
    if ($search_string =~ /^[0-9a-fA-F\-]+$/) {
        unless ($client = $c->m->resultset('MeritCommons::Plugin::OAuth2::Model::Client')->find({ unique_id => $search_string })) {
            unless ($client = $c->m->resultset('MeritCommons::Plugin::OAuth2::Model::Client')->find({ thumbprint => $search_string })) {
                # only search on ID if it's an integer
                if ($search_string =~ /^\d+$/) {
                    $client = $c->m->resultset('MeritCommons::Plugin::OAuth2::Model::Client')->find({ id => $search_string });
               }
           }
        }
    } else {
        $client = $c->m->resultset('MeritCommons::Plugin::OAuth2::Model::Client')->find({ common_name => $search_string });
    }

    return $client;
}

sub _scope {
    my ($c, $search_string) = @_;

    my $scope;
    if ($search_string =~ /^[0-9a-fA-F\-]+$/) {
        unless ($scope = $c->m->resultset('MeritCommons::Plugin::OAuth2::Model::Scope')->find({ unique_id => $search_string })) {
            $scope = $c->m->resultset('MeritCommons::Plugin::OAuth2::Model::Scope')->find({ id => $search_string })
        }
    } else {
        $scope = $c->m->resultset('MeritCommons::Plugin::OAuth2::Model::Scope')->find({ common_name => $search_string });
    }

    return $scope;
}

# verifies that a JWT is legit, returns undef if it's not good, or the data structure if it is good.
sub _verify_jwt {
    my ($c, $token) = @_;

    my ($header, $payload, $sig) = split(/\./, $token);
    
    # decode the data into perl hashrefs...
    my $hhr = decode_json(decode_base64url($header));
    my $phr = decode_json(decode_base64url($payload));

    if (my $client = $c->oauth2->client($phr->{iss})) {
        # signature_verifier does a bit of magic to figure out if we're doing shared secret or public
        # key sig checking
        my ($v_alg, $verifier) = $client->signature_verifier;

        if ($hhr->{alg} eq $v_alg) {
            # just a sanity check to make sure we have what we need to verify the jwt.
            if ($crypto->{$v_alg}->{verify}->($verifier, $sig, "$header.$payload")) {
                # extra info..
                $phr->{_verified_from_client} = $client->unique_id;
                $phr->{_verification_algorithm} = $v_alg;
                if (my $token = $c->oauth2->token($phr->{jti})) {
                    if ($token->is_refresh_token) {
                        $phr->{_is_refresh_token} = 1;
                    } else {
                        $phr->{_is_refresh_token} = 0;
                    }
                }
                return $phr;
            } else {
                warn "[oauth2] signature validation failed for jwt $phr->{jti}\n" if $ENV{MERITCOMMONS_DEBUG};
            }
        } else {
            warn "[oauth2] signature validation failed for jwt $phr->{jti}; credentials mismatch for client $phr->{iss}\n" if $ENV{MERITCOMMONS_DEBUG};
        }
    } else {
        warn "No client found for $phr->{iss}\n";
    }

    return undef;
}

sub _create_client {
    my ($c, $client_settings, $actor) = @_;

    if ($actor->has_role("developer") || $actor->is_admin) {
        if (!$c->oauth2->client($client_settings->{common_name})) {
            my $x509_string = $client_settings->{certificate};

            my ($certificate, $rsa_pk);
            if (!$client_settings->{meritcommons_certificate} && $x509_string) {
                $certificate = Crypt::X509->new(cert => b64_decode($x509_string));
                $rsa_pk = Crypt::PK::RSA->new(\$certificate->pubkey);
            } else {
                $certificate = $c->app->oauth2->rsa_x509;
                $x509_string = $c->app->oauth2->x509_string;
                $rsa_pk = $c->app->oauth2->rsa_pk;
            }

            my $callback_url = $client_settings->{callback_url} || "@{[$c->app->config->{front_door_url}]}/oauth2/callback";

            my $unique_id = $c->app->new_uuid;
            my $client_secret = $c->app->random_b64u(32);

            my $client = $c->app->m->resultset('MeritCommons::Plugin::OAuth2::Model::Client')->create({
                meritcommons_user => $actor->id,
                common_name => $client_settings->{common_name},
                unique_id => $unique_id,
                secret => $client_secret,
                certificate => $x509_string,
                thumbprint => $c->app->thumbprint($rsa_pk->export_key_der('public')),
                callback_url => $callback_url,
                description => $client_settings->{description},
            });

            if ($client) {
                return {
                    common_name => $client->common_name,
                    thumbprint => $client->thumbprint,
                    unique_id => $client->unique_id,
                    modify_time => $client->modify_time,
                    callback_url => $client->callback_url,
                    client_secret => $client_secret,
                    success => 1,
                };
            }
        } else {
            return {
                error => "The common name " . $client_settings->{common_name} . " has been taken.",
                success => 0,
            };
        }
    } else {
        return {
            error => "You do not have permission to do this.",
            success => 0,
        };
    }
}

sub _modify_client {
    my ($c, $client_settings, $actor) = @_;

    if (defined($actor) && ($actor->has_role("developer") || $actor->is_admin)) {
        if (my $client = $c->oauth2->client($client_settings->{unique_id} // $client_settings->{common_name})) {
            if ($client->meritcommons_user == $actor->id || $actor->is_admin) {
                my $callback_url = $client_settings->{callback_url} || "@{[$c->app->config->{front_door_url}]}/oauth2/callback";

                if ($client->common_name eq $client_settings->{common_name} || !$c->oauth2->client($client_settings->{common_name})) {
                    # update the client
                    $client->common_name($client_settings->{common_name});
                    $client->description($client_settings->{description});
                    $client->callback_url($callback_url);
                    $client->update();

                    return {
                        common_name => $client->common_name,
                        thumbprint => $client->thumbprint,
                        unique_id => $client->unique_id,
                        modify_time => $client->modify_time,
                        success => 1,
                    };
                } else {
                    return {
                        error => "The common name " . $client_settings->{common_name} . " has been taken.",
                        success => 0,
                    };
                }
            } else {
                return {
                    error => "You do not have permission to do this.",
                    success => 0,
                };
            }
        } else {
            return {
                error => "The client specified (" . $client_settings->{unique_id} . ") could not be found.",
                success => 0,
            };
        }
    } else {
        return {
            error => "You do not have permission to do this.",
            success => 0,
        };
    }
}

sub _remove_client {
    my ($c, $identifier, $actor) = @_;

    if (defined($identifier)) {
        if (defined($actor) && ($actor->has_role("developer") || $actor->is_admin)) {
            if (my $client = $c->oauth2->client($identifier)) {
                if ($client->meritcommons_user == $actor->id || $actor->is_admin) {
                    my $result = {
                        common_name => $client->common_name,
                        unique_id => $client->unique_id,
                        success => 1,
                    };
                    $client->delete;
                    return $result;
                } else {
                    return {
                        error => "You do not have permission to do this.",
                        success => 0,
                    };
                }
            } else {
                return {
                    error => "The client specified (" . $identifier . ") could not be found.",
                    success => 0,
                };
            }
        } else {
            return {
                error => "You do not have permission to do this.",
                success => 0,
            };
        }
    } else {
        return {
            error => "No client identifier specified.",
            success => 0,
        };
    }
}

sub _create_scope {
    my ($c, $scope_settings, $actor) = @_;

    if ($actor->has_role("developer") || $actor->is_admin) {
        if (!$c->oauth2->scope($scope_settings->{common_name})) {
            my $unique_id = $c->app->new_uuid;
            my $scope = $c->app->m->resultset('MeritCommons::Plugin::OAuth2::Model::Scope')->create({
                #meritcommons_user => $actor->id,
                common_name => $scope_settings->{common_name},
                unique_id => $unique_id,
                description => $scope_settings->{description},
            });

            if ($scope) {
                return {
                    common_name => $scope->common_name,
                    unique_id => $scope->unique_id,
                    modify_time => $scope->modify_time,
                    description => $scope->description,
                    success => 1,
                };
            }
        } else {
            return {
                error => "The common name " . $scope_settings->{common_name} . " has been taken.",
                success => 0,
            };
        }
    } else {
        return {
            error => "You do not have permission to do this.",
            success => 0,
        };
    }
}

sub _modify_scope {
    my ($c, $scope_settings, $actor) = @_;

    if (defined($actor) && ($actor->has_role("developer") || $actor->is_admin)) {
        if (my $scope = $c->oauth2->scope($scope_settings->{unique_id} // $scope_settings->{common_name})) {
            #if ($scope->meritcommons_user == $actor->id || $actor->is_admin) {
                if ($scope->common_name eq $scope_settings->{common_name} || !$c->oauth2->scope($scope_settings->{common_name})) {
                    # update the scope
                    $scope->common_name($scope_settings->{common_name});
                    $scope->description($scope_settings->{description});
                    $scope->update();

                    return {
                        common_name => $scope->common_name,
                        description => $scope->description,
                        modify_time => $scope->modify_time,
                        unique_id => $scope->unique_id,
                        success => 1,
                    };
                } else {
                    return {
                        error => "The common name " . $scope_settings->{common_name} . " has been taken.",
                        success => 0,
                    };
                }
            #} else {
            #    return {
            #        error => "You do not have permission to do this.",
            #        success => 0,
            #    };
            #}
        } else {
            return {
                error => "The scope specified (" . $scope_settings->{unique_id} . ") could not be found.",
                success => 0,
            };
        }
    } else {
        return {
            error => "You do not have permission to do this.",
            success => 0,
        };
    }
}

sub _remove_scope {
    my ($c, $identifier, $actor) = @_;

    if (defined($identifier)) {
        if (defined($actor) && ($actor->has_role("developer") || $actor->is_admin)) {
            if (my $scope = $c->oauth2->scope($identifier)) {
                #if ($scope->meritcommons_user == $actor->id || $actor->is_admin) {
                    my $result = {
                        common_name => $scope->common_name,
                        unique_id => $scope->unique_id,
                        success => 1,
                    };
                    $scope->delete;
                    return $result;
                #} else {
                #    return {
                #        error => "You do not have permission to do this.",
                #        success => 0,
                #    };
                #}
            } else {
                return {
                    error => "The scope specified (" . $identifier . ") could not be found.",
                    success => 0,
                };
            }
        } else {
            return {
                error => "You do not have permission to do this.",
                success => 0,
            };
        }
    } else {
        return {
            error => "No scope identifier specified.",
            success => 0,
        };
    }
}

1;