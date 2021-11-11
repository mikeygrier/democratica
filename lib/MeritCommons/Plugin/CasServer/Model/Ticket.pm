#    MeritCommons Portal
#    Copyright 2013 Wayne State University
#    All Rights Reserved

package MeritCommons::Plugin::CasServer::Model::Ticket;

use base qw/DBIx::Class/;
use Carp qw(croak);

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('ap_casserver_ticket');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type         => 'integer',
        is_numeric        => 1,
    },
    meritcommons_session => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
    ticket_id => {
        data_type => 'varchar',
        size      => 255,
    },
    service => {
        data_type => 'text',
    },
    pgt_url => {
        data_type   => 'text',
        is_nullable => 1,
    },
    issued_by_ticket => {
        data_type   => 'integer',
        is_numeric  => 1,
        is_nullable => 1,
    },
    consumed => {
        data_type  => 'integer',
        is_numeric => 1,
    },
    renew => {
        data_type  => 'integer',
        is_numeric => 1,
    },
    issue_time => {
        data_type  => 'integer',
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

__PACKAGE__->belongs_to(meritcommons_session   => 'MeritCommons::Model::Session', 
    undef, { cascade_delete => 0, is_foreign_key_constraint => 0 });
__PACKAGE__->belongs_to(issued_by_ticket => 'MeritCommons::Plugin::CasServer::Model::Ticket');

sub user {
    my ($self) = @_;
    return $self->meritcommons_session->meritcommons_user;
}

# alias to the above.
*meritcommons_user = \&user;

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

# build this in to the model
sub service_jstripped {
    my ($self) = @_;
    my $url = $self->service;
    $url =~ s/;jsession[^\?\b]+//;
    return $url;
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;

    $sqlt_table->add_index(
        name   => 'ap_casserver_ticket_ticket_id_idx',
        fields => ['ticket_id'],
    );

    $sqlt_table->add_index(
        name   => 'ap_casserver_ticket_session_idx',
        fields => ['meritcommons_session'],
    );

    $sqlt_table->add_index(
        name   => 'ap_casserver_ticket_create_time_idx',
        fields => ['create_time'],
    );
}
