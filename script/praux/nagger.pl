#!/usr/bin/env perl

use Praux;

my $praux = new Praux;

my ($email_file) = ($ARGV[0]);

unless ($email_file) {
    die "Usage: nagger.pl <email template>\n";
}

my $email_text;
open(SLURP, '<', $email_file);
{
    local $/;
    $email_text = <SLURP>;
}
close(SLURP);

use Mail::Sender;

my $s = Mail::Sender->new(
    {
        smtp => 'mail.mg2.org',
        from => 'Praux.com SysOp <sysop@praux.com>',
    }
);

foreach my $user ($praux->schema->resultset('User')->all) {
    print "Emailing " . $user->email . "\n";
    my $vars = {};
    my $local_email_text = $email_text;

    # skip those that don't want to be nagged!
    next if $user->preference('com.praux.mailnagoff');

    # populate vars..
    if (my $resume = $user->resume) {
        my $ri = $praux->resume_info($resume);
        $vars->{resume_summary} = "Congratulations!  You've created a resume, and are well on your way to success!\n\n";
        $vars->{resume_summary} .= "Resume Information For " . $resume->instance . ".praux.com\n";
        $vars->{resume_summary} .= "----------------------------------------\n";
        $vars->{resume_summary} .= "Completeness: " . $resume->percent_complete . "%\n";
        $vars->{resume_summary} .= "'PRAUX TIP' Blocks Remaining: " . $resume->tip_blocks_left . "\n";
        $vars->{resume_summary} .= "# of Visits to Your Resume: " . $ri->{hit_count} . "\n";
        $vars->{resume_summary} .= "Community Score: " . $ri->{score} . "\n" if $ri->{score};
        $vars->{resume_summary} .= "Resume available in " . scalar(@{$ri->{languages}}) . " language(s).\n" if scalar(@{$ri->{languages}});
        $vars->{important_links_text} .= "You can see all versions and formats of your resume at: http://" . $resume->instance . ".praux.com/important_links/";
    } else {
        $vars->{resume_summary} = "It doesn't look like you've created a resume yet!  For shame!\n";
        $vars->{important_links_text} .= "Get your resume started today to take advantage of this feature!";
    }

    $vars->{unsubscribe_url} = "http://praux.com/usersetpref/?k=com.praux.mailnagoff&back=http://praux.com/&v=1&u=" . $user->id;

    # get all the tags...
    my @tags;
    while ($local_email_text =~ /\<([\w\_\s]+)\>/gc) {
        push(@tags, $1);
    }

    # sub the tags out!
    foreach my $tag (@tags) {
        my $subst;
        if ($tag =~ /^_(.+)/) {
            $subst = $vars->{$1};
        } else {
            $subst = $user->$tag;
        }
        $local_email_text =~ s/\<$tag\>/$subst/g
    }

    $s->MailMsg(
        {
            to => $user->common_name . " <" . $user->email . ">",
            subject => "(P.c) The Praux.com Newsletter - February, 2010 - Apology Edition",
            msg => $local_email_text,
        }
    );
}
