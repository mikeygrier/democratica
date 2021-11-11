# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::SessionHeartbeat;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    my $page = $uri[1];

    $romeo->r->content_type('text/plain');
    if (my $user = $self->active_user) {
        print "PONG\n";
    } else {
        print "SESSION EXPIRED\n";
    }
    return OK;
}

1;
