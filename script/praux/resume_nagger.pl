#!/usr/bin/env perl

use Praux;

my $praux = new Praux;
my $nag_interval = 3600 * 24 * 14;
my $last_nag = 0;

# read in last nag..
open(LAST_NAG, '<', '/usr/local/var/resume_nagger-last_nag.dat');
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
    open(LAST_NAG, '>', '/usr/local/var/resume_nagger-last_nag.dat');
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

my $fr_email_text = <<"EOF";
Hello from Praux.com!

We were just noticing how complete your resume is looking, and wanted to
say great job.  It's important to take your online presence seriously
and it's obvious that you do.  

Did you know that only 40% of internet searches happen in English?  That
will more than likely keep your resume and information on the last pages
of the other 60%'s search results.  With Praux.com you can translate 
your resume into several languages and publish it in those languages. 
When you publish your content in other languages it becomes relevant to 
more searches!

Praux.com's translation engine uses Google Translate to translate all of
your content into any given language.  You can then receive suggestions
in that language from native speakers, and have a much more appealing, 
easy to find, and localized resume for the whole world to see.

To get started, log in to praux.com, select "Edit My Resume" and from
the drop down on the right, select another language you'd like to edit
your resume in, then click "Go!".  If Praux detects that your content
hasn't been translated yet, it will make an effort to translate your
content from your resume's default language into the language you
selected!  Your resume is now published in this language, and will
become much more relvant to people searching for you.. all over the
world!

Thank you again for using Praux.com!

--
The Praux.com Staff
sysop\@praux.com


P.S. If you don't want to get these mailings in the future, click below:
<_unsubscribe_url>

EOF

my $nr_email_text = <<"EOF";
Hey!

Thanks for using Praux.com, we're really excited that you've stumbled
upon our little lemonade stand here, and we want to make sure that you
get the most out of your new professional internet presence.

We've noticed that you've signed up for an account but you haven't yet
created a resume site.  These sites are cool, free-form documents that
you can fill with factoids about yourself.  Employers can subscribe to 
RSS feeds and get updates whenever you change something, you can
translate and publish your resume in several languages so your unique
skills can land you at the top of more piles.

Please take some time and navigate to: 

<_suggested_url> 

or any .praux.com url of your choice.  If it's not taken, and you're 
logged in, you will be able to claim it!  You can even move it once 
you've claimed it!  Nothing is written in stone.

We wish you luck in your career search, but now that you've found us, we
can make it easier for them to find you too.

--
The Praux.com Staff
sysop\@praux.com


P.S. If you don't want to get these mailings in the future, click below:
<_unsubscribe_url>

EOF

my $ur_email_text = <<"EOF";
Hey There!

Thanks for using Praux.com!  We've worked hard to give you a flexible
and competent format for publishing your resume online.  Our editor has
a great flow to it once you get using it.  You'll find that it works
with your creativity and writing style instead of against it.

We want to remind you to make the most out of your Praux.com
professional internet presence by completing your published Praux.com
resume!  You don't have to add a ton of content, just clean up what's
there.  People are searching and indexing Praux.com every day (just do
an internet search for yourself, and you'll see!).  Make sure there's
something there worth seeing!  Even if it's just a brief objective
statement and a list of skills.

Simply removing the default template text will go a long way toward
professionalizing your resume.  Right clicking content and then
selecting "Delete" from the menu will remove a content block including
all sub content.  So for the most part, you can clear out your resume in
6-8 clicks!  A few more and you can have some personal information
added.. a few more and you can apply one of our neat default styles to
spruce it up a bit!  And before you know it you have your best foot
forward.

To get you closer to the top of job recruiter's piles we're focusing 
on making sure our candidates are top quality.  By getting you resume 
to reflect 80% or more completeness, we'll make sure your resume gets 
properly indexed by search engines.  We'll also go through your resume 
and make helpful suggestions once it's reached the 80% mark as well.

So what are you waiting for?  They're out there searching for you.  Log
in to praux.com today and click "Edit My Resume", and spend 15-20
minutes giving your online professional image the attention it deserves.

Thanks again for using Praux.com!

--
The Praux.com Staff
sysop\@praux.com


P.S. If you don't want to get these mailings in the future, click below:
<_unsubscribe_url>

EOF

my ($email_text, $subject);
# one user per resume.. on email per resume.
foreach my $user ($praux->schema->resultset('User')->search({ verified => '1' })) {
    # honor nag preferences
    next if $user->preference('com.praux.mailnagoff');
    next if $user->preference('com.praux.resumemailnagoff');

    if (my $resume = $user->resume) {
        # skip non-english resumes
        next if $resume->default_language ne "en";
        if ($resume->completeness > 90) {
            # don't nag people taking advantage of all features..
            next if scalar($resume->languages) > 1;
            $email_text = $fr_email_text;
            $subject = "[praux] Your resume is looking great!";
        } else {
            $email_text = $ur_email_text;
            $subject = "[praux] It looks like your resume could use some work...";
        }
    } else {
        # no resume!
        $email_text = $nr_email_text;
        $subject = "[praux] Isn't it time to create your Praux.com resume?";
    }

    my $vars = {};
    # populate vars..

    $vars->{suggested_url} = 'http://' . $user->suggested_resume_host;
    $vars->{unsubscribe_url} = "http://praux.com/usersetpref/?k=com.praux.mailnagoff&v=1&u=" . $user->id;
    $vars->{refer_url} = "https://ssl.praux.com/r1/?ref=" . $user->id;

    # get all the tags...
    my @tags;
    while ($email_text =~ /\<([\w\_\s]+)\>/gc) {
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
        $email_text =~ s/\<$tag\>/$subst/g
    }

    print "Emailing " . $user->email . "\n";

    $s->MailMsg(
        {
            to => $user->common_name . " <" . $user->email . ">",
            subject => $subject,
            msg => $email_text,
        }
    );
}
