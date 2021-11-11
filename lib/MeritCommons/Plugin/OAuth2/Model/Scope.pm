package MeritCommons::Plugin::OAuth2::Model::Scope;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('ap_oauth2_scope');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type         => 'integer',
        is_numeric        => 1,
    },
    # uuid of scope
    unique_id => {
        data_type => 'varchar',
        size      => 64,
    },
    # the common name of the scope e.g. edu.wayne.cit.MobileApp
    common_name => {
        data_type => 'varchar',
        size => 255,
    },
    # the description of what this scope entails
    description => {
        data_type => 'text',
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
        name   => 'ap_oauth2_scope_unique_id_idx',
        fields => ['unique_id'],
    );

    $sqlt_table->add_index(
        name   => 'ap_oauth2_scope_common_name_idx',
        fields => ['common_name'],
    );
}

1;