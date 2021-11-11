package Praux::Url::QRcode;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use Apache2::SubRequest;

sub handle_request {
    my ($self, $romeo, @uri) = @_;

    if ($self->resume) {
        $romeo->r->content_type('image/png');
        print $self->resume->qrcode_png;
    } else {
        $romeo->r->internal_redirect("/img/pc.png");
    }
    
    return OK;
}

1;
