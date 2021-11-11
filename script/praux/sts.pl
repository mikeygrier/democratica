#!/usr/bin/env perl

my ($instance, $lang, $view) = @ARGV;

unless ($instance) {
    die "Usage: sts.pl <resume_host> <language> <view>\n";
}

$view = "default" unless $view;
$instance =~ s/^(.+)\.praux\.com/$1/g;

use Praux;
use Lingua::Stem::Snowball;
my $praux = new Praux;
$praux->{lang} = $lang;
$praux->{view} = $view;

my $stemmer = Lingua::Stem::Snowball->new(
    lang => $lang,
    encoding => 'UTF-8',
);

# stop list
my %stop_hash;
my @stop_words = qw/i in a to the it have haven't was but is be from been try tried tought by our -
for test then how those their suit up which come own also and over take while with per great between
would of as an on that or act
/;

foreach my $word (@stop_words) {
    $stop_hash{$word}++;
}

my $resume = $praux->resume_by_instance($instance);
my %unstemmed;
my %dont_stem;

# where the final data / counts are going..
my %final;

if ($resume) {
    print "[info] serializing and tokenizing $instance in $lang.  view: $view\n";

    # get all the visible items..
    my $content_items = $resume->content_items->search(
        {
            language => $lang,
            visible => 1,
        }
    );

    foreach my $vi ($content_items->all) {
        # skip section headers..
        next if $vi->content_block->format eq "section_header";


        # don't try and tokenize BBCode
        if ($vi->body && $vi->body !~ /\[\//) {
            # tokenize body by spaces..
            foreach my $word (split(/\s+/, $vi->body)) {
                if (exists($stop_hash{lc($word)})) {
                    next;
                } elsif ($word !~ /[A-Za-z]+/o) {
                    next;
                } elsif ($word =~ /[\,\.]+$/o) {
                    next;
                } elsif ($word =~ /^\(/o) {
                    next;
                } elsif ($word =~ /\)$/o) {
                    next;
                }
                $word =~ s/[\[\]\:]+//g;

                $unstemmed{lc($word)}++;
            }
        }

        # these should be most valuable as phrases!
        foreach my $method (qw/organization locality role instructor title/) {
            my $val = $vi->$method;
            $final{$val}++ if $val;
        }
    }

    # stem
    print "[info] stemming words in $lang...\n";
    foreach my $root_word (keys %unstemmed) {
        my $is_stemmed = 0;
        my $stem = $stemmer->stem($root_word, \$is_stemmed);
        if ($is_stemmed) {
            $final{$stem} += $unstemmed{$root_word};
        } else {
            $final{$root_word} += $unstemmed{$root_word};
        }
    }

    my @sorted_stemmed;
    foreach my $key (sort {$final{$b} <=> $final{$a}} keys %final) {
        $key =~ s/^\s*(.+?)\s*/$1/g;
        push(@sorted_stemmed, $key);
    }

    print join(', ', @sorted_stemmed) . "\n";
} else {
    die "Error: can't find resume instance $instance...\n";
}
