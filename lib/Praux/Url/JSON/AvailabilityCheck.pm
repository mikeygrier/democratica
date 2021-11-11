# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::JSON::AvailabilityCheck;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use JSON;

my $json = JSON->new();

sub handle_request {
    my ($self, $romeo, @uri) = @_;

	$romeo->r->no_cache(1);
	
	my ($instance) = $romeo->param('i');
	my ($user) = $romeo->param('u');
	
	my $return = {
	    success => 1,
	};
	
	if ($instance) {
	    if ($self->resume_by_instance($instance)) {
	        $return->{instance} = "Instance $instance is already taken!";
	    }
	}
	
	if ($user) {
	    if ($self->user_by_email($user)) {
	        $return->{user} = "User $user already has an account!";
	    }
	}
	
	$romeo->r->content_type('application/x-javascript');
    print $json->encode(
        $return,
    );
    return OK;
}

1;
