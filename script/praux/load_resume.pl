#!/usr/bin/env perl

my ($instance, $file) = @ARGV;

unless ($instance && $file) {
    die "Usage: load_resume.pl <resume_host> <filename>\n";
}

unless (-e $file) {
    die "Error: can't find resume file $file\n";
}

$instance =~ s/^(.+)\.praux\.com/$1/g;

use YAML::Syck;
use Praux;
my $praux = new Praux;

my $resume = $praux->resume_by_instance($instance);
my $data = LoadFile($file);

if ($resume) {
    print "Loading resume into $instance...\n";
} else {
    die "Error: can't find resume instance $instance...\n";
}

foreach my $section (@{$data->{sections}}) {
    # add the section..
    my $section_format =    $section->{jobs} ? 'job' :
                            $section->{projects} ? 'project' :
                            $section->{classes} ? 'course' :
                            $section->{tutorials} ? 'tutorial' : 'generic';

    my $sec = $praux->schema->resultset('Resume::Section')->create(
        {
            resume => $resume,
            format => $section_format,
        }
    );

    # add the section header block (where the content goes)
    my $cb = $praux->schema->resultset('Resume::ContentBlock')->create(
        {
            section => $sec,
            format => 'section_header',
            resume => $resume,
        }
    );

    # add the section header block content!
    $praux->schema->resultset('Resume::ContentItem')->create(
        {
            content_block => $cb,
            resume => $resume,
            body => $section->{section},
            resume => $resume,
            visible => 1,
            submitter => $resume->praux_user,
            create_time => time,
            modify_time => time,
        }
    );

    if ($section->{items}) {
        add_items($section->{items}, $sec, $cb);
    } 

    if ($section->{jobs}) {
        add_jobs($section->{jobs}, $sec, $cb);
    }

    if ($section->{projects}) {
        add_projects($section->{projects}, $sec, $cb);
    }

    if ($section->{classes}) {
        add_classes($section->{classes}, $sec, $cb);
    }

    if ($section->{tutorials}) {
        add_tutorials($section->{tutorials}, $sec, $cb);
    }
}

# this suckers are electrical
sub add_tutorials {
    my ($data, $section, $parent) = @_;
    foreach my $tutorial (@$data) {
        my $cb = $praux->schema->resultset('Resume::ContentBlock')->create(
            {
                section => $section,
                parent => $parent->id,
                format => 'course',
                resume => $resume,
            }
        );
        $praux->schema->resultset('Resume::ContentItem')->create(
            {
                content_block => $cb,
                title => $tutorial->{tutorial},
                date_range => $tutorial->{dates_tutaled},
                organization => $tutorial->{event},
                locality => $tutorial->{locality},
                instructor => $tutorial->{trainer},
                visible => 1,
                submitter => $resume->praux_user,
                create_time => time,
                modify_time => time,
                resume => $resume,
            }
        );

        # add items...
        add_items($tutorial->{items}, $section, $cb);
    }
}



sub add_classes {
    my ($data, $section, $parent) = @_;
    foreach my $class (@$data) {
        my $cb = $praux->schema->resultset('Resume::ContentBlock')->create(
            {
                section => $section,
                parent => $parent->id,
                format => 'course',
                resume => $resume,
            }
        );
        $praux->schema->resultset('Resume::ContentItem')->create(
            {
                content_block => $cb,
                title => $class->{title},
                date_range => $class->{dates_employed},
                organization => $class->{company},
                locality => $class->{locality},
                instructor => $class->{trainer},
                visible => 1,
                submitter => $resume->praux_user,
                create_time => time,
                modify_time => time,
                resume => $resume,
            }
        );

        # add items...
        add_items($class->{items}, $section, $cb);
    }
}

sub add_projects {
    my ($data, $section, $parent) = @_;
    foreach my $project (@$data) {
        my $cb = $praux->schema->resultset('Resume::ContentBlock')->create(
            {
                section => $section,
                parent => $parent->id,
                format => 'project',
                resume => $resume,
            }
        );
        $praux->schema->resultset('Resume::ContentItem')->create(
            {
                content_block => $cb,
                title => $project->{title},
                date_range => $project->{dates_employed},
                organization => $project->{company},
                locality => $project->{locality},
                role => $project->{role},
                visible => 1,
                submitter => $resume->praux_user,
                create_time => time,
                modify_time => time,
                resume => $resume,
            }
        );

        # add items...
        add_items($project->{items}, $section, $cb);
    }
}

sub add_jobs {
    my ($data, $section, $parent) = @_;
    foreach my $job (@$data) {
        my $cb = $praux->schema->resultset('Resume::ContentBlock')->create(
            {
                section => $section,
                parent => $parent->id,
                format => 'job',
                resume => $resume,
            }
        );
        $praux->schema->resultset('Resume::ContentItem')->create(
            {
                content_block => $cb,
                title => $job->{title},
                date_range => $job->{dates_employed},
                organization => $job->{company},
                locality => $job->{locality},
                visible => 1,
                submitter => $resume->praux_user,
                create_time => time,
                modify_time => time,
                resume => $resume,
            }
        );

        # add items...
        add_items($job->{items}, $section, $cb);
    }
}

sub add_items {
    my ($data, $section, $parent) = @_;
    return unless ref($data);
    use Data::Dumper;
    print Dumper($data);
    foreach my $item (@$data) {
        my $cb = $praux->schema->resultset('Resume::ContentBlock')->create(
            {
                section => $section,
                parent => $parent->id,
                format => 'generic',
                resume => $resume,
            }
        );
        $praux->schema->resultset('Resume::ContentItem')->create(
            {
                content_block => $cb,
                body => $item->{item},
                visible => 1,
                submitter => $resume->praux_user,
                create_time => time,
                modify_time => time,
                resume => $resume,
            }
        );

        # recurse if we FEEL THE NEED
        if ($item->{sub_items}) {
            add_items($item->{sub_items}, $section, $cb);
        }
    }
}
