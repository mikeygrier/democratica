#!/usr/bin/env perl

use Praux;

my $praux = new Praux;

printf("%-30s  %-20s  %20s\n", "Instance", "Tip Blocks Remaining", "Percent Complete");
print "-" x 80 . "\n";
foreach my $resume ($praux->schema->resultset('Resume')->all) {
    eval {
        printf("%-30s  %-20s  %20s%\n", $resume->instance, $resume->tip_blocks_left, $resume->percent_complete);
    };

    if (my $error = $@) {
        print "Weirdness with " . $resume->instance . ": $error\n";
    }

}

