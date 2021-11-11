# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::MoveResume;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Praux::Util::Zimbra;
use GD::Barcode::QRcode;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    my $page = $uri[1];

    my $resume = $self->active_user->resume;
    
    my $zimbra = Praux::Util::Zimbra->new(
        resume => $resume,
    );
    
    my $enable_mailmask = 0;
    if ($zimbra->mailmask_enabled) {
        $reenable_mailmask = 1;
        $zimbra->disable_mailmask;
    }
    
    $romeo->session->moved_from($resume->instance);
    $resume->instance($self->instance);

    # qrcode generate (a new one!)
    my $to_encode_string = 'http://' . $self->instance . $self->c->COOKIE_DOMAIN;
    my $qrcode_png = GD::Barcode::QRcode->new(
        $to_encode_string,
        {
            Ecc => 'L',
            Version => 6,
            ModuleSize => 6,
        }
    )->plot->png;
    $resume->qrcode_png($qrcode_png);

    # do the update!
    $resume->update();
    
    # clear all cache for this instance (thanks globalEK)..
    $self->clear_all_cache;

    # new mailmask on the flip.
    if ($reenable_mailmask) {
        $zimbra->enable_mailmask;
    }

    $romeo->r->content_type('text/html;charset=utf-8');
    $romeo->r->headers_out->set(Location => '/edit/');
    return REDIRECT;
}

1;
