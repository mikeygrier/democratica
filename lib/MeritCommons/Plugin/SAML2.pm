#
# A SAML2 IdP and SP plugin for MeritCommons
#

package MeritCommons::Plugin::SAML2;
use Mojo::Base 'MeritCommons::Plugin';
use Mojo::Util qw/b64_decode url_escape/;
use Mojo::File;
use Mojo::URL;
use Mojo::DOM;
use MeritCommons::Config;
use Mojo::Collection 'c';

# no openssl, avoid segfaults because of SSLeay
use Crypt::X509;
use Crypt::PK::RSA;
use Crypt::Digest qw/digest_data_hex/;

our $VERSION = 0.03;
our $SCHEMA_VERSION = 1;

# globals for other subs..
my ($rsa_sk, $rsa_pk, $rsa_x509, $x509_string, $config);
my $tp_idx = {};

# MeritCommons::Plugins use _register instead of register.
sub _register {
    my ($self, $app) = @_;

    # load (or generate) our keys
    my $crt_path = "$ENV{MERITCOMMONS_HOME}/etc/plugin/saml2/rsa.crt";
    my $key_path = "$ENV{MERITCOMMONS_HOME}/etc/plugin/saml2/rsa.key";

    my $find_keys = sub {
        # allow plugin configuration override...
        if (-e $key_path && -e $crt_path) {
            # load the secret key and cert.....
            my $key_text = Mojo::File->new($key_path)->slurp;
            my $test_rsa_sk = Crypt::PK::RSA->new(\$key_text);

            my $crt_text = Mojo::File->new($crt_path)->slurp;
            $x509_string = __unpem($crt_text);
            my $test_rsa_x509 = Crypt::X509->new( cert => b64_decode($x509_string) );
            my $test_rsa_pk = Crypt::PK::RSA->new(\$test_rsa_x509->pubkey);

            # test that this keypair matches..
            my $plaintext = "Hello, World!\n";
            my $sig = $test_rsa_sk->sign_message($plaintext, 'SHA256', 'v1.5');

            if ($test_rsa_pk->verify_message($sig, $plaintext, 'SHA256', 'v1.5')) {
                # this pair works, let's use it!
                $rsa_pk = $test_rsa_pk;
                $rsa_sk = $test_rsa_sk;
                $rsa_x509 = $test_rsa_x509;
                if ($ENV{MERITCOMMONS_DEBUG}) {
                    print "[saml2] using existing RSA keypair (Fingerprint: " . __fingerprint(b64_decode($x509_string)) . ")\n";
                    print "        Valid after " . localtime($rsa_x509->not_before) . "\n";
                    print "        Valid until " . localtime($rsa_x509->not_after) . "\n";
                }
            }
        } else {
            eval {
                # use the system certificate.
                $rsa_sk = $app->system_rsa_sk;
                $rsa_pk = $app->system_rsa_pk;
                $rsa_x509 = $app->system_rsa_cert;
                $x509_string = $app->system_rsa_cert_b64;
                if ($ENV{MERITCOMMONS_DEBUG}) {
                    print "[saml2] using system provided RSA keypair (Thumbprint: " . $app->system_rsa_thumbprint . ")\n";
                    print "        Valid after " . localtime($rsa_x509->not_before) . "\n";
                    print "        Valid until " . localtime($rsa_x509->not_after) . "\n";
                }
            };
        }
    };

    $find_keys->();

    $app->on(schema_deployed => sub {
        $find_keys->();
    });

    # our entity id in a helper
    my $entity_id = "@{[$app->global_config->{front_door_url}]}/saml2/trust";
    $app->helper('saml2.entity_id' => sub {
         return $entity_id;
    });

    $app->helper('saml2.fa_rs' => sub { 
        $app->m->resultset('MeritCommons::Plugin::SAML2::Model::FederationAgreement'); 
    });

    $app->helper('saml2.rsa_sk' => \&_rsa_sk);
    $app->helper('saml2.rsa_pk' => \&_rsa_pk);
    $app->helper('saml2.rsa_x509' => \&_rsa_x509);
    $app->helper('saml2.x509_string' => \&_x509_string);
    $app->helper('saml2.federation' => \&_federation);
    $app->helper('saml2.all_federations' => \&_all_federations);
    $app->helper('saml2.thumbprint_to_entity_id' => \&_thumbprint_to_entity_id);
    $app->helper('saml2.cert_to_entity_id' => \&_cert_to_entity_id);
    $app->helper('saml2.federation_from_thumbprint' => \&_federation_from_thumbprint);
    $app->helper('saml2.federation_from_cert' => \&_federation_from_cert);

    # load in utility methods
    $app->plugin('SAML2Util');

    # get the plugin config...
    $config = $self->plugin_config;

    # Routes!
    $app->routes->get('/saml2/metadata' => [format => ['xml']])->to('Plugin::SAML2::Controller::SAML2#metadata');
    $app->routes->get('/saml2/idp_initiated_sso')->to('Plugin::SAML2::Controller::SAML2#idp_initiated_sso');
    $app->routes->get('/saml2/ar')->to('Plugin::SAML2::Controller::SAML2#artifact_resolution');
    $app->routes->get('/saml2/http_redirect')->to('Plugin::SAML2::Controller::SAML2#sp_initiated_sso', http_redirect_binding => 1);
    $app->routes->route('/saml2/http_post')->via(qw/GET POST/)->to('Plugin::SAML2::Controller::SAML2#sp_initiated_sso', http_post_binding => 1);

    # some SPs insist upon sending SAMLRequests to the EntityID
    $app->routes->get('/saml2/trust')->to('Plugin::SAML2::Controller::SAML2#sp_initiated_sso', asserted_to_entity_id => 1);
    $app->routes->post('/saml2/trust')->to('Plugin::SAML2::Controller::SAML2#sp_initiated_sso', asserted_to_entity_id => 1);

    $app->routes->get('/saml2/entity/:entity_id/')->to('Plugin::SAML2::Controller::SAML2#idp_initiated_sso');

    $app->routes->get('/saml2/tar')->to('Plugin::SAML2::Controller::SAML2#test_authn_request');
    $app->routes->route('/saml2/logout')->to('Plugin::SAML2::Controller::SAML2#logout');
    
    # this is used to determine if we need to redirect to the auth_url
    $app->on(unauthenticated_access => sub {
        my ($app, $c) = @_;

        if ($c->req->url->path =~ /^\/saml2\/(?:metadata|ar)/o) {
            $c->stash(redirect_to_auth_url => 0);
        } else {
            # if something else already said don't redirect, then we don't redirect
            unless (defined $c->stash('redirect_to_auth_url') && $c->stash('redirect_to_auth_url') == 0) {
                $c->stash(redirect_to_auth_url => 1);
            }
        }
    });

    $app->on(external_preauth => sub {
        my ($app, $c, $user, $pass) = @_;
        
        if (my $cfo = $c->stash('created_from_override')) {
            $c->log->warn("saml2 - external_preauth not considering overriding created_from as it's already overridden with value $cfo");
            return; ## be good plugin neighbors!
        }
        
        if (my $destination_url = $c->param('destination_url')) {
            my $du = Mojo::URL->new($destination_url);
            if (my $authn_request = $du->query->param('SAMLRequest')) {
                my ($ar_xml, $ar_dom);
                eval {
                    if ($destination_url =~ /saml2\/http_redirect/) {
                        # http redirectg binding
                        $ar_xml = $c->saml2->inflate(b64_decode($authn_request));
                    } else { 
                        # default to http post
                        $ar_xml = b64_decode($authn_request);
                    }
                
                    $ar_dom = Mojo::DOM->new->xml(1)->parse($ar_xml);
                };
                if (my $error = $@) {
                    eval {
                          $ar_xml = b64_decode($authn_request);
                          $ar_dom = Mojo::DOM->new->xml(1)->parse($ar_xml);
                    };
                    if ($@) {
                        # if we still can't crack it just abort
                        $c->log->warn("saml2 - external_preauth - problem parsing SAMLRequest found in destination_url - $destination_url");
                        return; ## abort! abort!
                    }
                }

                if (my $issuer = $ar_dom->at('Issuer')->text) {
                    if (my $federation = $c->saml2->federation($issuer)) {
                        $c->stash('created_from_override', $app->config->{front_door_url} . "/saml2/entity/" . url_escape($federation->{entity_id}) . "/");
                        $c->auth_log("saml2 - external_preauth overriding created_from; new value @{[$c->stash('created_from_override')]}");
                    } else {
                        $c->log->info("saml2 - external_preauth considered request for $issuer, but we do not have a federation agreement with them");
                    }
                }
            }
        }
    });
        

    return $self;
}

# returns a Mojo::Collection of all federations
sub _all_federations {
    my ($self) = @_;

    return Mojo::Collection->new(map { $_->agreement } $self->saml2->fa_rs->all);
}

sub _thumbprint_to_entity_id {
    
    my ($c, $thumbprint) = @_;
    my $matches = $c->saml2->fa_rs->search({ thumbprint => $thumbprint });
    if ($matches->count > 1) {
        $c->log->warn("saml2 - $thumbprint resolves to more than one entity_id, returning first.  entities: " . join(', ', $matches->all));
    }
    
    return $matches->first->entity_id;
}

# for the ultra lazy (such as myself)
sub _cert_to_entity_id {
    my ($c, $pem) = @_;
    return $c->saml2->thumbprint_to_entity_id($c->thumbprint(b64_decode($pem)));
}

sub _federation_from_cert {
    my ($c, $pem) = @_;
    return $c->saml2->federation_from_thumbprint($c->thumbprint(b64_decode($pem)));
}

sub _federation_from_thumbprint {
    my ($c, $thumbprint) = @_;
    my $matches = $c->fa_rs->search({thumbprint => $thumbprint});
    if (my $federation = $matches->first) {
        return $federation;
    }
    return undef;
}

sub _federation {
    my ($self, $entity_id) = @_;

    # must pass entity id!
    return undef unless $entity_id;

    my $matches = $self->fa_rs->search({entity_id => $entity_id});
    if (my $federation = $matches->first) {
        return $federation->agreement;
    } else {
        print "[error] couldn't find federation configuration for $entity_id, try running:\n";
        print "        'meritcommons saml2 add_federation $entity_id'\n";
    }
}

sub _saml2_config {
    return $config;
}

sub _x509_string {
    return $x509_string;
}

sub _rsa_sk {
    return $rsa_sk;
}

sub _rsa_pk {
    return $rsa_pk;
}

sub _rsa_x509 {
    return $rsa_x509;
}

sub __fingerprint {
    my ($der) = @_;
    my $digest = digest_data_hex('SHA1', $der);
    return uc(join(':', ($digest =~ /.{2}/gs)));
}

sub __unpem {
    my ($pem) = @_;
    my $unpem = join('', split("\n", $pem));
    $unpem =~ s/-----[^-]+-----//g;
    return $unpem;
}

1;