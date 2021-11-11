#!/usr/bin/env perl

use Praux;
use WWW::Romeo;

my $romeo = new WWW::Romeo;

my $sessions = $romeo->db->resultset('Session');

print "Authenticated Sessions: " . $sessions->search({type => 'Praux'})->count . "\n";
foreach my $session ($sessions->search({type => 'Praux'})) {
    print " ++ active user: " . $session->external_user . "\n";
    if (my $attr = $session->attributes->search({ k => 'ip_address' })->first) {
        if ($attr->v !~ /^216.150.225/) {
            print "   ++ from ip: " . $attr->v . "\n";
        }
    }
}

print "Anonymous Sessions: " . $sessions->search({anonymous => 1})->count . "\n";
foreach my $session ($sessions->search({anonymous => 1})) {
    if (my $attr = $session->attributes->search({ k => 'ip_address' })->first) {
        if ($attr->v !~ /^216.150.225/) {
            print " ++ " . $session->session_id . " lurking from ip: " . $attr->v . "\n";
        }
    }
}
