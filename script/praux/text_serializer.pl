#!/usr/bin/env perl

use Text::Wrap qw/wrap $columns/;

my ($instance, $view, $lang) = @ARGV;

unless ($instance) {
    die "Usage: text_serializer.pl <resume_host>\n";
}

$instance =~ s/^(.+)\.praux\.com/$1/g;

use Praux;
my $praux = new Praux;

my $resume = $praux->resume_by_instance($instance);

# set the number of columns for wrap
$columns = 80;

if ($resume) {
    $lang = $resume->default_language unless $lang;
    $view = "default" unless $view;

    my $text;
    # thank you, thank you very much...
    if ($resume->address) {
        $text .= sprintf("Name: %-25s  Address: %-37s\n", $resume->name, $resume->address);
    } else {
        $text .= sprintf("Name: %-25s\n", $resume->name);
    }

    if ($resume->phone) {
        $text .= sprintf("Email: %-24s  Phone: %-20s\n", $resume->email, $resume->phone);
    } else {
        $text .= sprintf("Email: %-24s\n", $resume->email);
    }

    $text .= "\n";

    foreach my $section ($resume->sections) {
        # skip ones that aren't in this view!
        next unless $praux->has_view($section, $view);

        # get the section header content block!
        my $sec_cb = $section->header_cb;
        my $section_header = $sec_cb->visible_item($lang)->body or "Section Name";
        $text .= sprintf("%-80s\n", $section_header);
        $text .= "-" x 80 . "\n";

        my $count = $sec_cb->children->count;
        my $i;
        foreach my $cb ($sec_cb->sorted_children) {
            next unless $praux->has_view($cb, $view);
            my $vi = $cb->visible_item($lang);
            $i++;
            if ($cb->format eq "generic") {
                add_generic($cb, 0, \$text);
            } elsif ($cb->format eq "job") {
                $text .= sprintf("%-15s      %-25s      %28s\n", substr($vi->date_range ? $vi->date_range : "MM/DD", 0, 15),
                                                        substr($vi->organization ? $vi->organization : "Company Name", 0, 25),
                                                        substr($vi->locality ? $vi->locality : "City, ST", 0, 28));
                $text .= sprintf("                     %-60s\n", substr($vi->title ? $vi->title : "Title", 0, 60));
                foreach my $child ($cb->sorted_children) {
                    next unless $praux->has_view($child, $view);
                    add_generic($child, 0, \$text);
                }
                $text .= "\n" unless $i == $count;
            } elsif ($cb->format eq "project") {
                $text .= sprintf("%-15s      %-25s      %28s\n", substr($vi->date_range ? $vi->date_range : "MM/DD", 0, 15),
                                                        substr($vi->title ? $vi->title : "Project Name", 0, 25),
                                                        substr($vi->locality ? $vi->locality : "City, ST", 0, 28));
                $text .= sprintf("                     %-60s\n", substr($vi->organization ? $vi->organization : "Organization" . 
                                                        " - " . $vi->role ? $vi->role : "Project Role", 0, 60));
                foreach my $child ($cb->sorted_children) {
                    next unless $praux->has_view($child, $view);
                    add_generic($child, 0, \$text);
                }
                $text .= "\n" unless $i == $count;
            } elsif ($cb->format eq "course") {
                $text .= sprintf("%-15s      %-25s      %28s\n", substr($vi->date_range ? $vi->date_range : "MM/DD", 0, 15),
                                                        substr($vi->title ? $vi->title : "Course Name", 0, 25),
                                                        substr($vi->locality ? $vi->locality : "City, ST", 0, 28));
                $text .= sprintf("                     %-60s\n", substr($vi->instructor ? $vi->instructor : "Instructor", 0, 60));
                foreach my $child ($cb->sorted_children) {
                    next unless $praux->has_view($child, $view);
                    add_generic($child, 0, \$text);
                }
                $text .= "\n" unless $i == $count;
            }
        }
        $text .= "\n\n";
    }
    print "$text";
} else {
    die "Error: can't find resume instance $instance...\n";
}

sub add_generic {
    my ($cb, $depth, $textref) = @_;
    my $body = $cb->visible_item($lang)->body;
    $$textref .= wrap("    " x $depth . " * ", '', $body) . "\n";
    foreach my $child ($cb->children) {
        next unless $praux->has_view($child, $view);
        add_generic($child, $depth + 1, $textref);
    }
}
