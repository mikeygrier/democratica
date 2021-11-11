# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::FacebookAuth;

use base qw/Praux::Url::Component/;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

sub handle_request {
    my ($self, $romeo, @uri) = @_;

    $romeo->r->no_cache(1);
    
    my $fb_email;
    
    eval {
        $fb_email = $self->fb_email;
    };
    
    if ($self->fb->users->get_logged_in_user) {
        if ($self->active_user) {
            # already have a native session, wtf?
            $romeo->r->headers_out->set(Location => $self->active_user->resume->url . "/edit/");
            return REDIRECT;
        } elsif (my $user = $self->user_by_email($fb_email)) {
            # establish native session then pass on!
            $romeo->r->headers_out->set(Location => '/fb2praux/?back=' . $self->root_url);
            return REDIRECT;
        } else {
            # no native session or local account.. let's create a resume (and a local account)!
            $romeo->r->headers_out->set(Location => '/page/fb_create_resume/');
            return REDIRECT;
        }
    } else {
        # back to the front page cos we ain't got shit!
        $romeo->r->headers_out->set(Location => $self->root_url);
        return REDIRECT;
    }
}

1;
