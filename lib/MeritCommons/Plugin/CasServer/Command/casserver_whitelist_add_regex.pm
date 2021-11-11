#    MeritCommons Portal
#    Copyright 2013 Wayne State University
#    All Rights Reserved

package MeritCommons::Plugin::CasServer::Command::casserver_whitelist_add_regex;

use Mojo::Base 'Mojolicious::Command';

has description => "Add a CAS service URL to the whitelist\n";
has usage       => "Usage: $0 casserver_whitelist_add_regex [URL_REGEX]\n" .
                    "      Note: include boundary characters and modifiers\n" .
                    "      e.g. {^https://abc.example.com} or\n" .
                    "      /https:\/\/example.com\/\?app=omar/i (case insensitive)\n";

sub run {
    my ($self, $re) = @_;
    unless ($re) {
        print $self->usage;
        return;
    }

    my $boundary_char = subst($re, 0, 1);

    if ($boundary_char =~ /^[\/\|\{\(]/) {    
        if ($re =~ /^$boundry_char/ && $re =~ /$boundary_char\w*$/) {
            print "[info] Adding CAS whitelist URL Regex\n";
            $url = $self->app->m->resultset('MeritCommons::Plugin::CasServer::Model::Whitelist')->create({ regex => $re });
            return;
        } else {
            print "[error] poorly formatted regex: $re\n";
            print $self->usage;
            return;
        }
    } else {    
        print "[error] boundary characters must be /, |, {, or (\n";
        print $self->usage;
        return;
    }
    
}

1;
