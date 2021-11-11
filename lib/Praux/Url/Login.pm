package Praux::Url::Login;

@ISA = ('Praux::Url::Component');

use Praux::Url::Component;
use Apache2::Const qw /:common/;
use Apache2::Util qw /ht_time/;
use Carp;
use JSON;
use Praux::Session;

# create one instance... for all to use ;)
my $json = JSON->new;

sub handle_request {
    my ($self, $romeo, @args) = @_;

    $romeo->r->no_cache(1);

    # get rid of the first argument, used to dispatch through bN
    shift(@args);

    # unpack our arguments...
    my @uri = @args;
    my $page = $uri[0];

    my ($email, $password) = ($romeo->cgi->param('email'), $romeo->cgi->param('password'));

    my $back = $romeo->cgi->param('back');
    my $failback = $romeo->cgi->param('failback');
    my $successback = $romeo->cgi->param('successback');

    my $use_json = $romeo->cgi->param('json');

    if ($email && $password) {
        my $session = Praux::Session->new(
            User        =>      $email,
            Pass        =>      $password,
        );

        if ($session) {
            my $user = $session->praux_user;
            
            if ($user->verify_token eq "VERIFIED") {            
                # rock!
                $cookie = Apache2::Cookie->new(  $romeo->r,     -name       =>      'romeo_auth',
                                                                -value      =>      $session->session_id,
                                                                -path       =>      '/',
                                                                -domain     =>      $romeo->c->COOKIE_DOMAIN,
                                             );

                $cookie->bake($romeo->r);
                # this is only safe because it's the END of the request right here.. don't just
                # sub subclassed Session objects into the front end w/o reblessing them.
                #$romeo->{user_session} = $session; # bad self.. BAD... BAD BAD.

                # in fact...
                $romeo->{user_session} = bless($session, 'WWW::Romeo::Session'); # this is the right way to do it.

                if ($use_json) {
                    $romeo->r->content_type('application-x/javascript');
                
                    print $json->encode({ success => 1, message => 'Login Successful'});
                } else {
                    $romeo->session->tried($romeo->cgi->param('tried'));
                    if ($successback) {
                        $romeo->r->content_type('text/html;charset=utf-8');
                        $romeo->r->headers_out->set( Location => $successback );
                        return REDIRECT;
                    } elsif ($back) {
                        $romeo->r->content_type('text/html;charset=utf-8');
                        $romeo->r->headers_out->set( Location => $back );
                        return REDIRECT;
                    } else {
                        $romeo->r->content_type('text/html;charset=utf-8');
                        $self->render_page('logged_in');
                    }
                }
            } else {
                $romeo->session->login_error('Account Not Verified!');
                $romeo->r->content_type('text/html;charset=utf-8');
                $romeo->r->headers_out->set( Location => $back );
                return REDIRECT;
            }
        } else {
            # invalid login
            if ($use_json) {
                $romeo->r->content_type('application-x/javascript');
                print $json->encode({ success => 0, error => 'Invalid Login' });
            } else {
                $romeo->session->login_error('Invalid Login');
                if ($failback) {
                    $romeo->r->content_type('text/html;charset=utf-8');
                    $romeo->r->headers_out->set( Location => $failback );
                    return REDIRECT;
                } else {
                    $romeo->r->content_type('text/html;charset=utf-8');
                    $romeo->r->headers_out->set( Location => $back );
                    return REDIRECT;
                }
            }
        }
    } else {
        if ($self->active_user) {
            # we be already logged in..
            if ($use_json) {
                $romeo->r->content_type('application-x/javascript');
                
                $json->encode({ success => 1, message => 'Already logged in!' });
            } else {
                $romeo->r->content_type('text/html;charset=utf-8');
                
                $self->render_page('logged_in');
            }
        } else {                  
            $romeo->r->content_type('text/html;charset=utf-8');
            
            $self->render_page('login', {args => $page});
        }
    }
    return OK;
}

1;
