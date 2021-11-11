#!/usr/bin/env perl

use Praux;

my $praux = new Praux;
foreach my $user ($praux->schema->resultset('User')->search({ gravatar_url => undef })) {
    if ($praux->gravatar_exists($user->email)) {
        print "adding gravatar: " . $user->email . "\n";
        $user->gravatar_url($praux->gravatar_url($user->email));
        $user->update;
    }
}
