#!/usr/bin/env perl

my ($instance, $file) = @ARGV;

unless ($instance) {
    die "Usage: deserialize.pl <resume_host> <resume_file>\n";
}

$instance =~ s/^(.+)\.praux\.com/$1/g;

use Praux;
my $praux = new Praux;

open(FILE, '<', $file);

my $yaml;
{
    local $/; # slrup
    $yaml = <FILE>;
}

$praux->import_yaml_resume($yaml, $instance);


