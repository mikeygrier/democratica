#!/usr/bin/env perl

unless ($ARGV[1]) {
    die "Usage: set_all_user_pref.pl <key> <value>\n";
}

use Praux;

my $praux = new Praux;
foreach my $user ($praux->schema->resultset('User')->all) {
    next unless $user->resume;
    print $user->email . ": $ARGV[0] = $ARGV[1]\n";
    $user->preference($ARGV[0], $ARGV[1]);
}
