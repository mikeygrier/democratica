#!/usr/bin/env perl

use Praux;
use Net::Twitter;
use WWW::Shorten::Bitly;

my $bitly_login = "mikeygstyle";
my $bitly_apikey = "R_48757af1d4142f6c711536380fc8d756";

my $bitly = WWW::Shorten::Bitly->new(
    USER => $bitly_login,
    APIKEY => $bitly_apikey,
);

my $nt = Net::Twitter->new(
    traits   => [qw/API::REST/],
    username => 'prauxdotcom',
    password => 'Awesomejki99',
);

my $praux = new Praux;

# get everything in the last hour...
my $rs = $praux->schema->resultset('Log')->search( 
    {
        create_time => { '>', (time() - 3600) },
    }, 
    { 
        order_by => 'create_time DESC' 
    }
);

# get the resumes in their order of last edit..
my @resumes;
my $summaries = {};
foreach my $result ($rs->all) {
    my $resume = $result->resume;
    next unless $resume->completeness > 80;
    if ($result->action =~ /Order/) {
        push(@{$summaries->{$resume->instance}}, "re-ordered some content");
    } elsif ($result->action =~ /Edit/) {
        push(@{$summaries->{$resume->instance}}, "polished up a bit");
    } elsif ($result->action =~ /AddSuggestion/) {
        push(@{$summaries->{$resume->instance}}, "received some feedback");
    } elsif ($result->action =~ /Add/) {
        push(@{$summaries->{$resume->instance}}, "added some new experience");
    } elsif ($result->action =~ /Theme/) {
        push(@{$summaries->{$resume->instance}}, "changed the look and feel");
    } elsif ($result->action =~ /SetSuggestion/) {
        push(@{$summaries->{$resume->instance}}, "accepted a suggestion");
    } elsif ($result->action =~ /RemoveSuggestion/) {
        push(@{$summaries->{$resume->instance}}, "denied a suggestion");
    } elsif ($result->action =~ /Views/) {
        push(@{$summaries->{$resume->instance}}, "worked on a sub-resume");
    } elsif ($result->action =~ /Remove/) {
        push(@{$summaries->{$resume->instance}}, "got rid of some stuff");
    } elsif ($result->action =~ /Create/) {
        push(@{$summaries->{$resume->instance}}, "got things started");
    }

    my $already_listed;
    foreach my $listed (@resumes) {
        $already_listed = 1 if $listed->id == $resume->id;
    }
    push(@resumes, $resume) unless $already_listed;
}

foreach my $resume (@resumes) {
    my $string;
    if ($resume->name) {
        $string = (split(/\s+/, $resume->name))[0] . " just ";
    } else {
        $string = "Someone just ";
    }

    # uniq this array ref..
    my $ar = $summaries->{$resume->instance};
    my $hr = {};
    foreach my $ele (@$ar) {
        $hr->{$ele}++;
    }

    my @keys = keys %$hr;
    $ar = \@keys;

    if (scalar(@$ar) == 1) {
        $string .= $$ar[0];
    } else {
        for (my $i = 0; $i < scalar(@$ar); $i++) {
            if ($i == scalar(@$ar) - 1) {
                $string .= ", and $$ar[$i]";
            } elsif ($i == 0) {
                $string .= $$ar[$i];
            } else {
                $string .= ", $$ar[$i]";
            }
        }
    }
    $string .= " on their resume " . $bitly->shorten(URL => "http://" . $resume->instance . ".praux.com/") . " #resume";
    $nt->update($string);
}
