#!/usr/bin/env perl

my ($instance) = @ARGV;

unless ($instance) {
    die "Usage: serialize.pl <resume_host>\n";
}

$instance =~ s/^(.+)\.praux\.com/$1/g;

use Praux;
my $praux = new Praux;

my $resume = $praux->resume_by_instance($instance);

if ($resume) {
    print $resume->serialize_yaml;
} else {
    die "Error: can't find resume instance $instance...\n";
}
