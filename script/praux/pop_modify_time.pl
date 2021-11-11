#!/usr/bin/env perl

use Praux;

my $praux = new Praux;

my $rs = $praux->schema->resultset('Resume')->search_rs(undef);

foreach my $resume ($rs->all) {
    my $last_modify_time = $resume->changes(undef, { order_by => 'create_time DESC' })->first->create_time;
    $resume->modify_time($last_modify_time);
    $resume->update;
    print $resume->instance . ": $last_modify_time\n";
}
