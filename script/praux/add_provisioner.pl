#!/usr/bin/perl

use Praux;
my $praux = new Praux;
use Digest::MD5 qw/md5_hex/;

# provisioner name, contact name, contact email, passphrase, verify_email, create_resume, force_defaults
unless ($ARGV[3]) {
    die "Usage: add_provisioner.pl <provisioner_name> <contact_name> <contact_email> <passphrase> <verify_email> <create_resume> <force_defaults> <emblem_file>\n";
}

my ($pname, $cname, $cemail, $pass, $vemail, $cresume, $fdefaults, $emblem_file) = @ARGV;

my $efile_contents;
if (-e $emblem_file) {
    open(EFILE, '<', $emblem_file) or die "Can't read emblem file: $emblem_file! $!\n";
    {
        local $/;
        $efile_contents = <EFILE>;
    }
    close(EFILE);
}

my $key = $praux->new_uuid;
my $hash = md5_hex($key . $pass);

my $provisioner = $praux->schema->resultset('Provisioner')->create(
    {
        contact_email => $cemail,
        contact_name => $cname,
        common_name => $pname,
        provision_key => $key,
        provision_hash => $hash,
        emblem => $efile_contents,
        verify_email => defined($vemail) ? $vemail : 1,
        create_resume => defined($cresume) ? $cresume : 0,
        force_defaults => defined($fdefaults) ? $fdefaults : 0,
    }
);

print "Provisioner $pname created.\n";
print "Provision Key: " . $provisioner->provision_key . "\n";
