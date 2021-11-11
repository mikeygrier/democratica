#!/usr/bin/env perl

use Praux;

my $praux = new Praux;

my $rs = $praux->schema->resultset('Resume')->search_rs(undef);

foreach my $resume ($rs->all) {
    my $completeness = $resume->percent_complete;
    $resume->completeness($completeness);
    $resume->update;
    print $resume->instance . ": $completeness\n";
}
