package Praux::Url::JSON::SetSectionOrder;

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
                error => "Only the owner of this resume can set section order...",
            }
        );
        return OK;
    }
    
    my @order = $romeo->param('order');
    
    for (my $i = 0; $i < scalar(@order); $i++) {
        $sec = $self->sec($order[$i]);
        if ($sec->resume->id == $self->active_user->resume->id) {
            $sec->sort_order($i);
            $sec->update;
        } else {
            $romeo->r->content_type('application/x-javascript');
            print $json->encode(
                success => 0,
                error => "Out of bounds!  You just tried to change the sort order on a section you don't own!",
            );
            return OK;
        }
    }

    $self->log_action({
        action => __PACKAGE__,
        resume => $self->resume,
        instance => $self->resume->instance,
        acting_user => $self->active_user->id,
    });
    
    # clear the cache for this instance
    $self->clear_all_cache;
    
    $romeo->r->content_type('application/x-javascript');
    print $json->encode(
        {
            success => 1,
            general_message => 'Section order set successfully!',
        }
    );
    
    return OK;
}
1;
