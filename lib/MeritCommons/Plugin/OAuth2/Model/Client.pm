package MeritCommons::Plugin::OAuth2::Model::Client;

use base qw/DBIx::Class/;
use Mojo::Util qw/b64_decode b64_encode secure_compare encode/;
use Crypt::X509;
use Crypt::PK::RSA;
use Crypt::PK::ECC;
use Crypt::Sodium;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('ap_oauth2_client');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type         => 'integer',
        is_numeric        => 1,
    },
    meritcommons_user => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    # uuid of client
    unique_id => {
        data_type => 'varchar',
        size      => 64,
    },
    # the client's secret (used to authenticate the client)
    secret => {
        data_type => 'varchar',
        size => 255,
    },
    # the base64url encoded der of the client's x509 certificate
    certificate => {
        data_type => 'text',
        is_nullable => 1,
    },
    # a sha256_hex of the public key of the above
    thumbprint => {
        data_type => 'varchar',
        size => 255,
    },
    # the client's callback url
    callback_url => {
        data_type => 'varchar',
        size => 255,
    },
    # common name of this client
    common_name => {
        data_type => 'varchar',
        size => 255,
    },
    # description of this client
    description => {
        data_type => 'text',
        is_nullable => 1,
    },
    create_time => {
        data_type  => 'integer',
        is_numeric => 1,
    },
    modify_time => {
        data_type  => 'integer',
        is_numeric => 1,
    },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->belongs_to(meritcommons_user          => 'MeritCommons::Model::User');
__PACKAGE__->has_many(tokens                    => 'MeritCommons::Plugin::OAuth2::Model::Token');
__PACKAGE__->add_unique_constraint(common_name  => ['common_name']);

# allow the client row object to emit what we use to verify signatures.  sometimes
# this will be a public key, sometimes this will be a shared secret (HMAC)
sub signature_verifier {
    my ($self) = @_;

    my ($type, $verifier);
    if ($self->certificate) {
        my $x509 = Crypt::X509->new( cert => b64_decode($self->certificate) );

        if ($x509->pubkey_algorithm =~ /^1\.2\.840\.113549\.1\.1\./) {
            # this key is RSA
            $type = 'RS256';
            $verifier = Crypt::PK::RSA->new(\$x509->pubkey);
        } elsif ($x509->pubkey_algorithm eq '1.2.840.10045.2.1') {
            # this key is ECDSA
            $type = 'ES256';
            $verifier = Crypt::PK::ECC->new(\$x509->pubkey);
        }
    } else {
        $type = 'HS256';
        $verifier = $self->secret;
    }

    return wantarray ? ($type, $verifier) : $verifier;
}

# a redirect of my own to follow naming conventions of RFC 6749
sub redirect_url {
    shift->callback_url(@_);
}

# do this extra stuff on insert
sub insert {
    my ($self, @args) = @_;
    $self->create_time(time);
    $self->modify_time(time);
    $self->secret(_salted_digest($self->secret, 20, 10240));
    $self->next::method(@args);
}

sub update {
    my ($self, @args) = @_;
    $self->modify_time(time);
    if ($self->is_column_changed('secret')) {
        $self->secret(_salted_digest($self->secret, 20, 10240));
    }    
    $self->next::method(@args);
}

sub authenticate {
    my ($self, $password) = @_;
    return _compare_salted_digest($password, $self->secret);
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;

    $sqlt_table->add_index(
        name   => 'ap_oauth2_client_unique_id_idx',
        fields => ['unique_id'],
    );

    $sqlt_table->add_index(
        name   => 'ap_oauth2_client_common_name_idx',
        fields => ['common_name'],
    );

    $sqlt_table->add_index(
        name   => 'ap_oauth2_client_thumbprint_idx',
        fields => ['thumbprint'],
    );
}

sub _compare_salted_digest {
    my ($cleartext, $digest) = @_;

    # make sure we're UTF-8 encoded
    $cleartext = encode('UTF-8', $cleartext);

    # parse the header
    my ($iterations, $algorithm, $encoded) = $digest =~ /^\{(\d+)x([^\}]+)\}(.+)$/;

    unless ($algorithm eq "SSHA512") {
        warn "[fatal]: unsupported algorithm $algorithm\n";
        return undef;
    }

    my ($hash, $salt) = map { b64_decode($_) } split(':', $encoded);

    my $compare = $cleartext;
    for (my $i = 0; $i < $iterations; $i++) {
        $compare = crypto_hash("$compare$salt");
    }

    if (secure_compare($hash, $compare)) {
        return 1;
    }

    return undef;
}

sub _salted_digest {
    my ($cleartext, $salt_length, $iterations) = @_;

    # make sure we're UTF-8 encoded
    $cleartext = encode('UTF-8', $cleartext);

    my $salt = randombytes_buf($salt_length);

    my $hash = $cleartext;
    for (my $i = 0; $i < $iterations; $i++) {
        $hash = crypto_hash("$hash$salt");
    }

    return "{${iterations}xSSHA512}" . b64_encode($hash, '') . ":" . b64_encode($salt, '');
}

1;