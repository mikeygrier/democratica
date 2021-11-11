package Praux::Tools::CreateCollection;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use JSON;

my $json = new JSON;

sub handle_request {
    my ($self, $romeo, @uri) = @_;

    $romeo->r->content_type('application/x-javascript');
    print $json->encode(
        {
            success => 0,
            error => "Praux knows about whatever it is you're trying to do, but can't do anything about it.",
        }
    );
    return OK;
}
1;
