#!/usr/bin/env perl

use Praux;

my $praux = new Praux;

my $rs = $praux->schema->resultset('Resume')->search_rs(undef);

foreach my $resume ($rs->all) {
    my $summary = $resume->random_excerpts;
    $resume->summary($summary);
    $resume->update;
    print $resume->instance . ": $summary\n";
}
