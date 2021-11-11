#!/usr/bin/env perl

use Praux;
use GD::Barcode::QRcode;

my $praux = new Praux;

my $rs = $praux->schema->resultset('Resume')->search_rs(undef);

foreach my $resume ($rs->all) {
    my $to_encode_string = 'http://' . $resume->instance . $praux->c->COOKIE_DOMAIN;
    my $qrcode = GD::Barcode::QRcode->new(
        $to_encode_string,
        {
            Ecc => 'L',
            Version => 6,
            ModuleSize => 6,
        }
    )->plot->png;
    $resume->qrcode_png($qrcode);
    $resume->update;
    print $resume->instance . ": a PNG image of " . length($qrcode) . " length!\n";
}
