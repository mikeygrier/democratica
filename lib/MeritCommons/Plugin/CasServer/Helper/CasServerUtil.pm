#    MeritCommons Portal
#    Copyright 2013 Wayne State University
#    All Rights Reserved

package MeritCommons::Plugin::CasServer::Helper::CasServerUtil;
use Mojo::Base 'Mojolicious::Plugin';
use Carp qw/croak/;
use Mojo::Util qw(b64_encode url_escape url_unescape);
use Mojo::URL;
use Crypt::Digest qw/digest_data digest_data_hex digest_data_b64/;

sub register {
    my ($self, $app) = @_;

    $app->helper('casserver.create_ticket'                  => \&_casserver_create_ticket);
    $app->helper('casserver.delete_leaf_nodes'              => \&_casserver_delete_leaf_nodes);
    $app->helper('casserver.delete_tickets_by_user'         => \&_casserver_delete_tickets_by_user);
    $app->helper('casserver.whitelist_match'                => \&_whitelist_match);
}

sub _whitelist_match {
    my ($self, $url) = @_;
    my $rs = $self->m->('MeritCommons::Plugin::CasServer::Model::Whitelist')->search;
    while (my $row = $rs->next) {
        my $re = $row->regex;
        my @rec = split(/\//, $re);
        eval "\$re = qr/$rec[1]/$rec[2]";
        if ($url =~ $re) {
            return 1;
        }
    }
    return 0;
}

sub _casserver_delete_tickets_by_user {
    my ($self, $user) = @_;

    my $rs = $self->m->resultset('MeritCommons::Plugin::CasServer::Model::Ticket')->search(
        {
            'meritcommons_user.id' => $user->id
        },
        {
            join => { meritcommons_session => ['meritcommons_user'] },
            distinct => 1,
        }
    );

    while (my $row = $rs->next) {
        my ($more, $session_id) = (undef, $row->meritcommons_session->id);
        do {
            $more = $self->casserver->delete_leaf_nodes(1, $row->meritcommons_session->id);
        } until (!$more);
    }
}

sub _casserver_delete_leaf_nodes {
    my ($self, $immediate, $session_id) = @_;

    my $expiration_watermark = time - $self->casserver->plugin_config->{ticket_storage_expiration};

    my $leaf_tickets = $self->app->m->resultset('MeritCommons::Plugin::CasServer::Model::Ticket')->search(
        {
            issued_by_ticket => { '!=', undef }
        }
    );

    my $conditions;
    if ($session_id) {
        $conditions = {
            'me.id' => {
                -not_in => $leaf_tickets->get_column('issued_by_ticket')->as_query
            },
            meritcommons_session => $session_id,
        };
    } else {
        $conditions = {
            'me.id' => {
                -not_in => $leaf_tickets->get_column('issued_by_ticket')->as_query
            }
        };
    }

    unless ($immediate) {
        $conditions->{issue_time} = { '<' => $expiration_watermark };
    }

    my $tickets = $self->app->m->resultset('MeritCommons::Plugin::CasServer::Model::Ticket')->search($conditions);

    my $delete_count = $tickets->count;

    if ($delete_count > 0) {
        $tickets->delete_all;
    }

    return $delete_count;
}

sub _casserver_create_ticket {
    my ($self, $type, $service, $time, $renew, $pgt_url, $issued_by_ticket_id, $saml11) = @_;

    my $ticket_id;
    if ($saml11) {
        # format the artifact so that it's SAML compliant:
        # base64 encoded (two-byte "TypeCode" + 20-byte SourceID (CAS Server) + 20-byte assertion handle)
        my $type_code = 0x0001;
        my $source_id = digest_data('SHA1', $self->global_config->{identity_server});
        my $assertion_handle = digest_data('SHA1', $self->app->new_uuid);
        $ticket_id = b64_encode($type_code . $source_id . $assertion_handle, '');
    } else {
        $ticket_id = $type . "-" . $self->app->new_uuid;
    }

    my $ticket = $self->app->m->resultset('MeritCommons::Plugin::CasServer::Model::Ticket')->create(
        {
            "meritcommons_session"  => $self->meritcommons_session->id,
            "ticket_id"          => $ticket_id,
            "service"            => $service,
            "renew"              => $renew,
            "pgt_url"            => $pgt_url,
            "consumed"           => 0,
            "issue_time"         => $time,
            "issued_by_ticket"   => $issued_by_ticket_id
        }
    );

    return $ticket;
}

1;
