#    MeritCommons Portal
#    Copyright 2013 Wayne State University
#    All Rights Reserved

package MeritCommons::Plugin::CasServer::Command::casserver_whitelist_delete_regex;

use Mojo::Base 'Mojolicious::Command';

has description => "Remove a CAS service URL from the whitelist\n";
has usage       => "Usage: $0 casserver_whitelist_delete_regex [ID]\n";

sub run {
    my ($self, $id) = @_;
    unless ($id) {
        print $self->usage;
        return;
    }

    my $url = $self->app->m->resultset('MeritCommons::Plugin::CasServer::Model::Whitelist')->search({ id => $id })->first();

    if ($url) {
        print "[info] Deleting CAS whitelist URL Regex\n";
        $url->delete();
    } else {
        print "[info] URL Regex could not be found\n";        
    }
}

1;
