# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::OpenID;

use base qw/Praux::Url::Component/;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use Net::OpenID::Server;

sub handle_request {
    my ($self, $romeo, @uri) = @_;

    $romeo->r->no_cache(1);
    
    if (!$self->resume || ($self->instance eq "www" || $self->instance eq "ssl" || $self->instance eq "")) {
        $romeo->r->content_type('text/html');
        $romeo->render_error("You have to visit /id/ from an occupied resume!");
        return OK;
    } else {
        my $resume_url = $self->resume->instance . $self->c->COOKIE_DOMAIN; 
        my $openid = Net::OpenID::Server->new(
            post_args => $romeo->cgi,
            get_args => $romeo->cgi,
            endpoint_url => $resume_url . "/id/",
            server_secret => $self->c->OPENID_SECRET,
            setup_url => "http://$resume_url/page/openid_login/",
            
            # get user subroutine...
            get_user => sub {
                if ($self->active_user) {
                    return $self->active_user;
                }
                return undef;
            },
            
            # get_identity subroutine
            get_identity => sub {
                return $self->resume->instance . $self->c->COOKIE_DOMAIN;
            },
            
            # is this this user's resume?
            is_identity => sub {
                my ($u, $identity) = @_;
                return undef unless $u;
        
                if ('http://' . $u->resume->instance . $self->c->COOKIE_DOMAIN . "/id/" eq $identity) {
                    return 1;
                }
                return undef;
            },
            
            # we trust them if they're them.
            is_trusted => sub {
                my ($u, $trust_root, $is_identity) = @_;
                return $is_identity;
            },  
        );
        
        my ($type, $data) = $openid->handle_page();
        if ($type eq "redirect") {
            $romeo->r->headers_out->set(Location => $data);
            return REDIRECT;
        } elsif ($type eq "setup") {
            my $back_url = "http://$resume_url/id/?" . $self->romeo->r->args;
            $back_url =~ s/\&/\%26/g;
            $romeo->r->headers_out->set(Location => $openid->setup_url . "?back=$back_url");
            return REDIRECT;
        }
        
        # or just do it &trade;
        $romeo->r->content_type($type);
        print $data;
        return OK;
    }
}

1;
