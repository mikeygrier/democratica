#!/usr/bin/perl

use strict;
use Praux;

my $praux = new Praux;

if (!$praux->schema->get_db_version()) {
    # deploy this beeeeya
    $praux->schema->deploy();
} else {
    $praux->schema->upgrade();
}
