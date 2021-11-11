package Praux::Url::JSON::GetViews;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use JSON;

my $json = new JSON;

#
# kk .. this is a blues riff in b, watch me for the changes...
# and try to keep up. 
#

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    # if we're not logged in, do nothing
    unless ($self->active_user) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "You have to be logged in please...",
            }
        );
        return OK;
    }

    # only the owner can create content blocks.
    unless ($self->active_user->id == $self->resume->praux_user->id) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Only the owner of this resume can see the views... why dont you go get them for me?",
            }
        );
        return OK;
    }
    
    my $cb = $self->cb($romeo->param('content_block'));
    
    if ($cb->resume->praux_user->id == $self->active_user->id) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 1,
                views => $cb->view_names,
            }
        );
    } else {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "You are not the owner of this content block!  You can not see the views!",
            }
        );
    }
    
    return OK;
}

1;