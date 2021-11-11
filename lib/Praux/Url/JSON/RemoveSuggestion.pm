package Praux::Url::JSON::RemoveSuggestion;

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

    # i edited this comment.
    unless ($romeo->param_was_sent('suggestion')) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Must specify suggestion in remove_suggestion request.",
            }
        );
        return OK;
    }

    # get the suggestion object.
    my $suggestion = $self->suggestion($romeo->param('suggestion'));

    # check edit access
    my $can_edit = 0;
    if ($self->active_user->id == $suggestion->resume->praux_user->id) {
        # resume owners can edit anything in their resume (looks like i have to bubble way up for security)
        $can_edit = 1;
    }

    unless ($can_edit) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "You do not have access to edit this content.",
            }
        );
        return OK;
    }

    # we are clear here for deletion.
    $suggestion->delete;
    
    $self->log_action({
        section => $suggestion->content_item->content_block->section->id,
        content_block => $suggestion->content_item->content_block->id,
        content_item => $suggestion->content_item->id,
        suggestion => $suggestion->id,
        action => __PACKAGE__,
        resume => $suggestion->resume->id,
        instance => $suggestion->resume->instance,
        acting_user => $self->active_user->id,
    });
    
    $romeo->r->content_type('application/x-javascript');
    print $json->encode(
        {
            success => 1,
            general_message => "Suggestion " . $suggestion->id . " successfully removed!",
            suggestion => $suggestion->id,
            content_item => $suggestion->content_item->id,
        }
    );
    
    return OK;
}

1;
