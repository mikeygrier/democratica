# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::UserSetPref;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    my $page = $uri[1];

    my $k = $romeo->param('k');
    my $v = $romeo->param('v');
    my $back = $romeo->param('back');
    
    if (my $user = $self->active_user) {
        $user->preference($k, $v);
        $self->clear_all_cache;
    } elsif ($k eq "com.praux.mailnagoff") {
        # allow unauthenticated users to disable email nags.. for anyone ;)
        if (my $user = $self->user_by_id($romeo->param('u'))) {
            $user->preference($k, $v);
        }
    }
    
    if ($back) {
        $romeo->r->headers_out->set(Location => $back);
        return REDIRECT;
    } else {
        $romeo->r->headers_out->set(Location => $self->is_dev ? "http://prauxdev.com" : "http://praux.com");
    }
    return REDIRECT;
}

1;
