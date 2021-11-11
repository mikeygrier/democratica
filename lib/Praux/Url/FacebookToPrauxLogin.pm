package Praux::Url::FacebookToPrauxLogin;

@ISA = ('Praux::Url::Component');

use Praux::Url::Component;
use Apache2::Const qw /:common/;
use Apache2::Util qw /ht_time/;
use Carp;
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

    my $back = $romeo->cgi->param('back');

    # unless we have a user that matches all these criteria, forget it!
    unless ($self->schema->resultset('User')->search({
        email => $self->fb_email,
        external_id => $self->fb->users->get_logged_in_user,
        external_type => fb
    })->first) {
        $romeo->r->headers_out->set( Location => $self->root_url );
        return REDIRECT;
    }
        

    # double, then triple check this session.. to do so we have to pass romeo into the session object
    my $session = Praux::Session->new(
        User        =>      $self->fb_email,
        Pass        =>      'A&VBbgb42%H^@^ABDFzxB',
        romeo       =>      $romeo,
    );

    $cookie = Apache2::Cookie->new(  $romeo->r,     -name       =>      'romeo_auth',
                                                    -value      =>      $session->session_id,
                                                    -path       =>      '/',
                                                    -domain     =>      $romeo->c->COOKIE_DOMAIN,
                                 );

    $cookie->bake($romeo->r);

    # update the user the first time they log in w/ facebook!
    my $user = $session->praux_user;
    
    unless ($user->external_id) {
        $user->external_id($self->fb->users->get_logged_in_user);
        $user->external_type('fb');    
    }

    # this act also verifies unverified users!
    unless ($user->verified) {
        $user->verified('1');
        $user->verify_token('VERIFIED');
    }
    
    $user->update();
    $romeo->r->headers_out->set( Location => $back );
    return REDIRECT;

}
1;
