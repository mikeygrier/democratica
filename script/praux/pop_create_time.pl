#!/usr/bin/env perl

use Praux;

my $praux = new Praux;

my $rs = $praux->schema->resultset('Log')->search_rs(
    {
        action => 'Praux::Url::CreateResume',
    }
);

foreach my $log ($rs->all) {
    my $create_time = $log->create_time;
    my $resume = $log->resume;
    if ($resume->in_storage) {
        print "Setting " . $resume->instance . " ($resume) create time to $create_time\n";
        $resume->create_time($create_time);
        $resume->update;
    }
}
