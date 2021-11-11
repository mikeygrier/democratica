#!/usr/bin/env perl

use Praux;

my $praux = new Praux;
my $nag_interval = 3600 * 24 * 14;
my $last_nag = 0;

# read in last nag..
open(LAST_NAG, '<', '/usr/local/var/sug_nagger-last_nag.dat');
$last_nag = <LAST_NAG>;
chomp($last_nag);
close(LAST_NAG);

my $we_run = 0;
if ($last_nag) {
    my $check = $last_nag + $nag_interval;
    my $time = time;

    # give or take a day
    if ($time - 86400 < $check && $time + 86400 > $check) {
        # time is within one day.. we run!
        $we_run = 1;
    }
} else {
    $we_run = 1;
}

if ($we_run) {
    # set the last nag..
    open(LAST_NAG, '>', '/usr/local/var/sug_nagger-last_nag.dat');
    print LAST_NAG time . "\n";
    close(LAST_NAG);
} else {
    # we don't run now ;)
    exit();
}

use Mail::Sender;

my $s = Mail::Sender->new(
    {
        smtp => 'mail.mg2.org',
        from => 'Praux.com SysOp <sysop@praux.com>',
    }
);

my $email_text = <<"EOF";
Praux.com Suggestion Digest 

Praux.com allows other users to make suggestions on your resume's content, you should 
periodically check and either accept or remove the suggestions they make from the system.

For you convenience, every 14 days, we will send out this Suggestion Digest outlining all 
of the suggestions that we have in the system that are pending your review.  Suggestions 
not acted on after 90 days will be removed from our system.

The following suggestions have been made and are pending your review:

EOF

# get a list of users we're going to email
my $users = {};
foreach my $sug ($praux->schema->resultset('Resume::ContentItem::Suggestion')->all) {
    next unless $sug->resume->praux_user;
    $users->{$sug->resume->praux_user->id} = $sug->resume->praux_user;
}

foreach my $user (values %$users) {
    # honor mail nagging prefs..
    next if $user->preference('com.praux.mailnagoff');
    next if $user->preference('com.praux.sugmailnagoff');

    my $local_email = $email_text;
    my $added = 0;
    foreach my $sug ($user->resume->suggestions->search( { used => 0 })->all) {
        if ($sug->content_item && $sug->content_item->content_block) {
            if ($sug->create_time + (3600 * 24 * 90) < time) {
                $sug->delete;
            } else {
                $local_email .= "Suggestion By: " . $sug->submitter->common_name . "\n";
                $local_email .= "Review URL: http://" . $user->resume->instance . ".praux.com/edit/" . $sug->content_item->language . "/.suggestions_for/" . $sug->html_id . "/\n";
                $local_email .= "FROM: ";
                $local_email .= $sug->current_value . "\n";
                $local_email .= "TO: ";
                $local_email .= $sug->suggested_value . "\n\n";
                $added++;
            }
        } else {
            $sug->delete;
        }
    }

    if ($added) {
        my $unsub_url = "http://praux.com/usersetpref/?k=com.praux.mailnagoff&v=1&u=" . $user->id;
        $local_email .= <<"EOF";
----------------------
Resumes by Praux.com
suggestions\@praux.com
----------------------

p.s. if you do not wish to receive email notifications from Praux.com visit:
$unsub_url

EOF
        print "Emailing " . $user->email . "\n";

        $s->MailMsg(
            {
                to => $user->common_name . " <" . $user->email . ">",
                subject => "[praux] Resume Suggestion Digest For " . $user->resume->instance . ".praux.com",
                msg => $local_email,
            }
        );
    }
}
