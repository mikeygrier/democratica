#!/usr/bin/env perl

my $archive_dir = "/var/praux/backup";

print "(P.c) Praux.com resume archiver startup...\n";

use Praux;
my $praux = Praux->new();
print "Found " . $praux->schema->resultset('Resume')->count . " resumes to back up..\n";
print "Obtaining DB Handle from DBIx::Class... ";
my $dbh = $praux->schema->storage->dbh;
if ($dbh) {
    print "Done.\n";
} else {
    die "Error retrieving generic dbh from DBIx::Class::Schema\n";
}

foreach my $resume ($praux->schema->resultset('Resume')->all) {
    local $| = 1;
    my (@t) = localtime;
    my $y =  ($t[5] + 1900);
    my $m = sprintf("%02d", ($t[4] + 1));
    my $d = sprintf("%02d", $t[3]);

    # make the directories
    unless (-d "$archive_dir/$y") {
        mkdir("$archive_dir/$y");
        chmod(oct('2755'), "$archive_dir/$y");
    }

    unless (-d "$archive_dir/$y/$m") {
        mkdir("$archive_dir/$y/$m");
        chmod(oct('2755'), "$archive_dir/$y/$m");
    }

    unless (-d "$archive_dir/$y/$m/$d") {
        mkdir("$archive_dir/$y/$m/$d");
        chmod(oct('2755'), "$archive_dir/$y/$m/$d");
    }
        
    my $fn = $archive_dir . "/$y/$m/$d/" . $resume->instance . $praux->c->COOKIE_DOMAIN . ".yaml";
    print "Archiving " . $resume->instance . "... ";
    open(FH, '>', $fn);
    print FH $resume->serialize_yaml;
    close(FH);
    print "Done.\n";
}
