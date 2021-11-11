package Praux::Url::Logout;

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
    my ($self, $romeo, @uri) = @_;

    $romeo->r->no_cache(1);

    # get rid of the first argument, used to dispatch through bN
    shift(@args);

    # unpack our arguments...
    my @uri = @args;
    my $page = $uri[0];

    $cookie = Apache2::Cookie->new(  $romeo->r,     -name       =>      'romeo_auth',
                                                    -value      =>      '',
                                                    -path       =>      '/',
                                                    -domain     =>      $romeo->c->COOKIE_DOMAIN,
                                 );

    $cookie->bake($romeo->r);
    $romeo->r->content_type('text/html;charset=utf-8');
    $romeo->r->headers_out->set( Location => $romeo->app_base );
    return REDIRECT;
}

1;
