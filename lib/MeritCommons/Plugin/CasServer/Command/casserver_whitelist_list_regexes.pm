#    MeritCommons Portal
#    Copyright 2013 Wayne State University
#    All Rights Reserved

package MeritCommons::Plugin::CasServer::Command::casserver_whitelist_list_regexes;

use Mojo::Base 'Mojolicious::Command';

has description => "List the URLs in the CAS service whitelist\n";
has usage       => "Usage: $0 casserver_whitelist_list_regexes\n";

sub run {
    my ($self) = @_;

    my @records = $self->app->m->resultset('MeritCommons::Plugin::CasServer::Model::Whitelist')->all();

    print "ID\tURL\n";

    foreach my $record (@records) {
        print $record->id . "\t" . $record->regex."\n";
    }
}

1;
