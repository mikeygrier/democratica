# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::Page;

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

    for my $opt (@uri[2..$#uri]) {
        $romeo->param($opt  =>  1);
    }
	
    $romeo->r->content_type('text/html;charset=utf-8');
    $self->render_page($page);
    return OK;
}

1;
