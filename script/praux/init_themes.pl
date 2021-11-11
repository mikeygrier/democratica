#!/usr/bin/perl

#
# wipes out and initializes global themes!
#

use WWW::Romeo;
use Praux;

my $praux = new Praux;
my $romeo = new WWW::Romeo;

if (my $dir = $romeo->c->PRAUX_THEME_DIR) {
    if (-d $dir) {
        print "Found configured theme dir: $dir... Empty? (y/n): ";
        my $yn = <STDIN>;
        if ($yn =~ /^Y/i) {
            print "Deleting everything you ever did...\n";
            system("rm -rvf $dir/*");
            $praux->schema->resultset('Resume::Theme')->delete;
            sleep 1;
            print "Done..\n\nOkay.. I'm guessing praux is installed in /usr/local/praux..\n";
            if (-d "/usr/local/praux") {
                print "Yep.. ok.. looking for resume_themes..\n";
                if (-d "/usr/local/praux/resume_themes") {
                    print "Okay.. it looks like we're sufficiently nested in conditionals... now then..\n";
                    opendir(DIR, '/usr/local/praux/resume_themes');
                    while (my $sdir = readdir(DIR)) {
                        next if $sdir =~ /^\./;
                        print "Installing $sdir...\n";
                        my $deploy_uuid = $praux->new_uuid;
                        my $deploy_dir = $dir . "/" . $deploy_uuid . "/";
                        my $source_dir = '/usr/local/praux/resume_themes/' . $sdir;
                        system("mkdir $deploy_dir");
                        system("cp -rv $source_dir/* $deploy_dir");
                        $praux->schema->resultset('Resume::Theme')->create(
                            {
                                theme_name => $sdir,
                                owner => 1,
                                resume => 1,
                                deploy_type => 'global',
                                deploy_uuid => $deploy_uuid,
                            }
                        );
                    }
                } else {
                    die "[error]: where the hell are your themes?!\n";
                }
            } else {
                die "[error]: where the hell is praux?\n";
            }
        } else {
            die "[abort]: user said no.  no means no.\n";
        }
    } else {
        die "[error]: theme dir not present!\n";
    }
} else {
    die "[error]: PRAUX_THEME_DIR not set in the config!\n";
}
   
