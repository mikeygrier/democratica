#!/usr/bin/perl

use Praux;
use JSON;
use LWP::UserAgent;
my $praux = new Praux;
my $devprod = "prauxdev";
$| = 1;

my $VERSION = "1.0";

unless ($ARGV[0]) {
    die "Usage: provision.pl <provisioner_name>\n";
}

my ($pname) = @ARGV;

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

print "Provisioner '$pname' found, key: " . $provisioner->provision_key . "\n";
print "Trusting local account provision.\n\n";
print "Please paste user / resume parameters in k=v form, one per line, extra blank line ends...\n";

my %params;
while (my $line = <STDIN>) {
    chomp($line);
    last unless $line;
    my ($k, $v) = split(/=/, $line);
    $params{$k} = $v;
}

my ($theme_file, $default_template_file);
print "Create a resume too? (y/n) [n]: ";
my $response = <STDIN>;
if ($response =~ /^Y/i) {
    $params{create_resume} = 1;
    print "Install a theme file with this resume? (y/n) [n]: ";
    my $response = <STDIN>;
    if ($response =~ /^Y/i) {
        until (-e $theme_file) {
            print "Please enter the path to the theme file you wish to install: ";
            $theme_file = <STDIN>;
            chomp($theme_file);
        }
    }
    print "Install default resume content from a YAML file? (y/n) [n]: ";
    my $response = <STDIN>;
    if ($response =~ /^Y/i) {
        until (-e $default_template_file) {
            print "Please enter the path to the YAML resume content: ";
            $default_template_file = <STDIN>;
            chomp($default_template_file);
        }
    }
} else {
    $params{create_resume} = 0;
}

print "\n-- New User Summary --\n";
foreach my $key (keys %params) {
    print "$key: $params{$key}\n";
}

print "\n";

print "Upload theme file: $theme_file\n" if $theme_file;
print "Upload resume content from: $default_template_file\n" if $default_template_file;

print "\n";

print "Attempt to create user with these attributes? (y/n) [n]: ";
my $response = <STDIN>;
unless ($response =~ /^Y/i) {
    print "User aborted!\n";
    exit();
}

# put the files in there
$params{resume_template} = [$default_template_file];
$params{install_theme} = [$theme_file];
$params{provision_hash} = $provisioner->provision_hash;
$params{provision_key} = $provisioner->provision_key;

my $ua = new LWP::UserAgent;
my $json = new JSON;
$ua->agent('Praux Provisioner Utility v' . $VERSION);

my $resp = $ua->post('http://' . $devprod . '.com/pt/pv.json', 
    [
        %params,
    ], 'Content_Type' => 'form-data',
);

if ($resp->is_success) {
    my $hr = $json->decode($resp->decoded_content);
    if ($hr->{success} == 0) {
        die "Prauxvision Error: [error] $hr->{error}\n";
    } else {
        use Data::Dumper;
        print Dumper($hr);
    }
} else {
    die $resp->status_line;
}
