#!/usr/bin/env perl

use Praux;

my $praux = new Praux;
my $day = 3600 * 24;
my $first_time = 1258434000;
my $total = 0;

for (my $i = $first_time; $i < time; $i += $day) {
    my $lower = $i - $day;
    my $rs = $praux->schema->resultset('Log')->search_rs(
        {
            -and => [
                create_time => { '>=', $lower },
                create_time => { '<=', $i },
                action => 'Praux::Url::CreateResume',
            ],
        }
    );
    my $localtime = localtime($lower);
    $localtime =~ s/00:00:00 //g;
    print $localtime . "," . $rs->count . "\n";
    $total += $rs->count;
}

print "Total: $total\n";
