package MeritCommons::Plugin::OAuth2;

# Plugin that implements an OAuth2 IdP and Client
our $VERSION = 0.02;
our $SCHEMA_VERSION = 1;

use Mojo::Base 'MeritCommons::Plugin';
use Mojo::Util qw/b64_decode/;
use Mojo::File;
use MeritCommons::Config;

# import crypto libraries
use Crypt::X509;
use Crypt::PK::RSA;
use Crypt::Digest qw/digest_data_hex/;

# globals for other subs
my ($crt_text, $rsa_sk, $rsa_pk, $rsa_x509, $x509_string);

# MeritCommons Plugins use _register instead of register.
sub _register {
    my ($self, $app) = @_;

    # put the config in the global
    my $config = $self->plugin_config;

    # load (or generate) our keys
    my $crt_path = "$ENV{MERITCOMMONS_HOME}/etc/plugin/oauth2/rsa.crt";
    my $key_path = "$ENV{MERITCOMMONS_HOME}/etc/plugin/oauth2/rsa.key";

    my $find_keys = sub {
        # allow plugin configuration override...
        if (-e $key_path && -e $crt_path) {
            # load the secret key and cert.....
            my $key_text = Mojo::File->new($key_path)->slurp;
            my $test_rsa_sk = Crypt::PK::RSA->new(\$key_text);

            $crt_text = Mojo::File->new($crt_path)->slurp;
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
                    print "[oauth2] using existing RSA keypair (Fingerprint: " . __fingerprint(b64_decode($x509_string)) . ")\n";
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
                $crt_text = $app->system_rsa_cert_pem;

                if ($ENV{MERITCOMMONS_DEBUG}) {
                    print "[oauth2] using system provided RSA keypair (Thumbprint: " . $app->system_rsa_thumbprint . ")\n";
                    print "        Valid after " . localtime($rsa_x509->not_before) . "\n";
                    print "        Valid until " . localtime($rsa_x509->not_after) . "\n";
                }
            };
        }
    };

    $find_keys->();

    my $install_fixtures = sub {
        $find_keys->();

        unless (my $client = $app->m->resultset('MeritCommons::Plugin::OAuth2::Model::Client')->find({
            common_name => $app->config->{front_door_url} . "/oauth2/trust",
        })) {
            # if it doesn't exist yet, create it!
            my $client_secret = $app->random_b64u(32);
            $client = $app->m->resultset('MeritCommons::Plugin::OAuth2::Model::Client')->create({
                meritcommons_user => 1, # meritcommons system user
                common_name => $app->config->{front_door_url} . "/oauth2/trust",
                unique_id => $app->new_uuid,
                secret => $client_secret,
                certificate => $x509_string,
                thumbprint => $app->thumbprint($rsa_pk->export_key_der('public')),
                callback_url => "@{[$app->config->{front_door_url}]}/oauth2/callback",
                description => $app->config->{service_organization},
            });

            # print and save this secret
            print "[oauth2] created system client with secret: $client_secret\n";
            unless (-d "$ENV{MERITCOMMONS_HOME}/../var/plugins/oauth2") {
                system("mkdir -p $ENV{MERITCOMMONS_HOME}/../var/plugins/oauth2");
            }

            unless ($ENV{MERITCOMMONS_TESTING}) {
                Mojo::File->new("$ENV{MERITCOMMONS_HOME}/../var/plugins/oauth2/client_secret.txt")->spurt($client_secret);
            }

            foreach my $scope (@{$self->plugin_config->{default_scopes}}) {
                unless (my $row = $app->oauth2->scope($scope->{common_name})) {
                    $app->m->resultset('MeritCommons::Plugin::OAuth2::Model::Scope')->create({
                        unique_id => $app->new_uuid,
                        common_name => $scope->{common_name},
                        description => $scope->{description},
                    });
                }
            }
        }
    };

    # make sure we have a system-wide OAuth2 Client configured, but only once the server's listening
    $app->on(schema_deployed => $install_fixtures);
    $app->on(schema_upgraded => $install_fixtures);

    unless ($self->plugin_config->{signature_method}) {
        die "[fatal] MeritCommons::Plugin::OAuth2 - signature_method not found in $ENV{MERITCOMMONS_HOME}/etc/plugin/oauth2.conf - did you configure the plugin?\n";
    }

    $app->helper('oauth2.rsa_sk' => \&_rsa_sk);
    $app->helper('oauth2.rsa_pk' => \&_rsa_pk);
    $app->helper('oauth2.rsa_x509' => \&_rsa_x509);
    $app->helper('oauth2.x509_string' => \&_x509_string);
    $app->helper('oauth2.x509_pem' => \&_crt_text);

    $app->routes->get('/oauth2/rsa/pubkey' => [format => ['pem']])->to('Plugin::OAuth2::Controller::Endpoints#rsa_pubkey');
    $app->routes->route('/oauth2/authorization_request')->via(qw/GET POST/)->to('Plugin::OAuth2::Controller::Endpoints#authorization_request');
    $app->routes->route('/oauth2/authorization_grant')->via(qw/GET POST/)->to('Plugin::OAuth2::Controller::Endpoints#authorization_grant');
    $app->routes->route('/oauth2/access_token')->via(qw/GET POST/)->to('Plugin::OAuth2::Controller::Endpoints#access_token');
    $app->routes->route('/oauth2/callback')->via(qw/GET POST/)->to('Plugin::OAuth2::Controller::Endpoints#callback');
    $app->routes->route('/oauth2/verify_token')->via(qw/GET POST/)->to('Plugin::OAuth2::Controller::Endpoints#verify_token');
    $app->routes->route('/oauth2/o2a')->via(qw/GET POST/)->to('Plugin::OAuth2::Controller::Endpoints#oauth2_to_meritcommons');

    # web interface
    $app->routes->route('oauth2/list')->to('Plugin::OAuth2::Controller::Web#list');

    # load in utility methods
    $app->plugin('OAuth2Util');

    return $self;
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

sub _crt_text {
    return $crt_text;
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