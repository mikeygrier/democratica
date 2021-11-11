#    MeritCommons Portal
#    Copyright 2017 Wayne State University
#    All Rights Reserved

package MeritCommons::Plugin::SAML2::Model::FederationAgreement;

use base qw/DBIx::Class/;
use Carp qw(croak);
use JSON::XS;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('ap_saml2_federation_agreement');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type         => 'integer',
        is_numeric        => 1,
    },
    thumbprint => {
        data_type => 'varchar',
        size      => 255,
    },
    entity_id => {
        data_type => 'varchar',
        size => 255,
    },
    metadata_id => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    source_uri => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    type => {
        data_type => 'enum',
        is_enum   => 1,
        extra     => {
            list => [qw/service_provider identity_provider/],
        }
    },
    agreement => {
        data_type => 'json',
    },
    encryption_key_history => {
        data_type => 'json',
        is_nullable => 1,
        default_value => '[]',
    },
    signing_key_history => {
        data_type => 'json',
        is_nullable => 1,
        default_value => '[]',
    },
    encryption_key_expire_time => {
        data_type => 'integer',
        is_numeric => 1,
    },
    signing_key_expire_time => {
        data_type => 'integer',
        is_numeric => 1,
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

__PACKAGE__->inflate_column(agreement => {
    inflate => sub { decode_json( +shift ) },
    deflate => sub {
        my ($json) = @_;
        ref $json ? encode_json($json) : $json;
    }, 
});

__PACKAGE__->inflate_column(encryption_key_history => {
    inflate => sub { decode_json( +shift ) },
    deflate => sub {
        my ($json) = @_;
        ref $json ? encode_json($json) : $json;
    }, 
});

__PACKAGE__->inflate_column(signing_key_history => {
    inflate => sub { decode_json( +shift ) },
    deflate => sub {
        my ($json) = @_;
        ref $json ? encode_json($json) : $json;
    }, 
});


# do this extra stuff on insert
sub insert {
    my ($self, @args) = @_;
    $self->create_time(time);
    $self->modify_time(time);
    $self->next::method(@args);
}

sub update {
    my ($self, @args) = @_;
    $self->modify_time(time);
    $self->next::method(@args);
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;

    $sqlt_table->add_index(
        name   => 'ap_saml2_federation_agreement_entity_id_idx',
        fields => ['entity_id'],
    );

    $sqlt_table->add_index(
        name   => 'ap_saml2_federation_agreement_thumbprint_idx',
        fields => ['thumbprint'],
    );
}