#!/usr/bin/env perl

my $yeah = `ps -ef | grep soffice.bin | grep -v grep | wc -l`;
chomp($yeah);

unless ($yeah) {
    system("/usr/lib/openoffice/program/soffice.bin -accept='socket,host=localhost,port=8100;urp;StarOffice.ServiceManager' -norestore -nofirststartwizard -nologo -headless &");
}
