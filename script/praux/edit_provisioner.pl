#!/usr/bin/perl

use Praux;
my $praux = new Praux;

unless ($ARGV[1]) {
    die "Usage: edit_provisioner.pl <provisioner_name> <key> <value>\n";
}

my ($pname, $k, $v) = @ARGV;

my $from_file = 0;
if ($v) {
    if (-e $v) {
        print "$v is a file, set the preference value to the contents of file $v? (y/n) [n]: ";
        my $response = <STDIN>;
        if ($response =~ /^Y/i) {
            $from_file = $v;
        }
    }
    
    if ($from_file) {
        open(FILE, '<', $v);
        {
            local $/;
            $v = <FILE>;
        }
        close(FILE);
    }
}
    
my $rs = $praux->schema->resultset('Provisioner')->search(
    {
        common_name => $pname,
    }
);

my $provisioner;
if ($rs->count > 1) {
    print "More than one match found...\n";
    foreach my $row ($rs->all) {
        print "[" . $row->id . "] " . $row->common_name . ", " . $row->contact_name . ", " . $row->contact_email . "\n";
    }
    until ($provisioner) {
        print "Which one?: ";
        my $response = <STDIN>;
        chomp($response);
        foreach my $row ($rs->all) {
            if ($row->id == $response) {
                $provisioner = $row;
            }
        }
        print "Invalid Response!\n\n" unless $provisioner;
    }
} else {
    $provisioner = $rs->first;
}

if ($v) {
    if ($provisioner->can($k)) {
        $provisioner->$k($v);
        $provisioner->update;
    } else {
        print "Error: Provisioners can't $k!\n";
    }
    
    if ($from_file) {
        print "Set value of $k to the contents of $from_file!\n";
    } else {
        print "Set the value of $k to $v!\n";
    }
} else {
    if ($provisioner->can($k)) {
        print "The value of $k is:\n";
        print $provisioner->$k . "\n";
    } else {
        print "Provisioner can't $k\n";
    }
}
