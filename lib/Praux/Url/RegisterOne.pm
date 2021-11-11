# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::RegisterOne;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    my $page = $uri[1];
	$romeo->r->no_cache(1);
    $romeo->r->content_type('text/html;charset=utf-8');
    
    $self->session->register_email($romeo->param('email'));
    $self->session->register_password($romeo->param('password'));
    
    # don't overwrite existing referrals ;)
    $self->session->register_referral($romeo->param('ref')) unless $self->session->register_referral;
    
    $self->render_page('register');
    return OK;
}

1;
