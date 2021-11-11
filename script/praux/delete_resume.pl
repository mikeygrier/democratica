#!/usr/bin/env perl

my ($instance) = @ARGV;

unless ($instance) {
    die "Usage: delete_resume.pl <resume_host>\n";
}

$instance =~ s/^(.+)\.praux\.com/$1/g;

use Praux;
my $praux = new Praux;

my $resume = $praux->resume_by_instance($instance);

if ($resume) {
    print "Deleting $instance...\n";
    $resume->content_blocks->delete();
    $resume->delete();
    print "Done.\n";
} else {
    die "Error: can't find resume instance $instance...\n";
}
