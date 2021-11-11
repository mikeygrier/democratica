#    MeritCommons Portal
#    Copyright 2013 Wayne State University
#    All Rights Reserved

package MeritCommons::Plugin::CasServer::Command::casserver_prune_tickets;

use Mojo::Base 'Mojolicious::Command';

has description => "Delete CAS tickets that have expired\n";

sub run {
    my ($self) = @_;

    print "[info] Deleting old CAS tickets\n";

    # CAS tickets can issue other CAS tickets, so they can form a self-referencing parent/child
    # relationship.  The ancestry must be retained as long as the last ticket is valid, so that
    # the relationship can be identified.  Once the ticket data is no longer needed, the tickets
    # can be deleted, but they must be deleted in reverse order so that FK constraints are not
    # violated.  This loop deletes expired tickets in batches of levels, from newest to oldest.
    my $total_delete_count = 0;
    while (my $delete_count = $self->app->casserver->delete_leaf_nodes(0)) {
        $total_delete_count += $delete_count;
    }

    if ($total_delete_count == 0) {
        print "[info] No tickets are old enough to be purged\n";
    } elsif ($total_delete_count > 1) {
        print "[info] Deleted " . $total_delete_count . " ticket" . (($total_delete_count == 1) ? undef : "s") . "\n";
    }
}

1;
