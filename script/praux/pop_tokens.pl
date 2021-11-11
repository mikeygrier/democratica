#!/usr/bin/env perl

use Praux;

my $praux = new Praux;

my $rs = $praux->schema->resultset('Resume')->search_rs(undef);

foreach my $resume ($rs->all) {
    my ($high) = $praux->sts($resume, $resume->default_language, "all");
    my $tokens = join(',', @$high);

    $tokens = $praux->truncate($tokens, 255, 0);
    $tokens =~ s/,\w+$//g;

    $resume->tokens($tokens);
    $resume->update;
    print $resume->instance . ": $tokens\n";
}
