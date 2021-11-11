#!/usr/bin/perl

use strict;
use Praux;

my $start_version = $ARGV[0];

my $praux = new Praux;

unless ($start_version) {
    $start_version = $praux->schema->schema_version - 0.001;
}

$praux->schema->create_ddl_dir(
    'MySQL',
    $praux->schema->schema_version,
    '/root/praux-svn/schema/upgrades/',
    $start_version,
);
