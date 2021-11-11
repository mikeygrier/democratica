package Praux::Url::JSON::SetSuggestion;

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
                error => "Must specify suggestion in set_suggestion request.",
            }
        );
        return OK;
    }
    
    # our suggestion
    my $suggestion = $self->suggestion($romeo->param('suggestion'));
    my $suggestion_final_value = $romeo->param('suggestion_final_value');
    my $ci = $suggestion->content_item;
    my $cb = $ci->content_block;
    
    # check to make sure we can edit it.
    my $can_edit = 0;
    if ($self->active_user->id == $cb->resume->praux_user->id) {
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
    
    # ok .. we have access here, let's do the edit.
    
    # get the class..
    my $class = shift(@uri);
    
    # in case we have it -- for daisy chaining
    my $json_return = $romeo->param('json_return') || {};
    
    # initialize "our" arrayref.  we can not call ourselves, we have to take care 
    # of all our work, is that too much to ask?
    $json_return->{$class} = [] unless $json_return->{$class};

    # take note that we used this suggestion.
    if ($suggestion->suggested_value eq $suggestion_final_value) {
        $suggestion->verbatim(1);
    } else {
        $suggestion->derivative(1);
    }
    
    $suggestion->used(1);
    $suggestion->used_time(time);
    
    my $old_yaml = $ci->serialize_yaml;
    
    # set this.
    my $suggested_attribute = $suggestion->suggested_attribute;
    $ci->$suggested_attribute($suggestion_final_value);
    
    # commit our changes.
    $suggestion->update;
    $ci->update;

    push(@{$json_return->{$class}}, 
        {
            message => "Accepted suggestion for $suggested_attribute",
            html_id => $cb->id . "-$suggested_attribute",
            block_id => $cb->id,
            item_id => $ci->id,
            display_value => $ci->$suggested_attribute,
        }
    );

    $self->log_action({
        section => $suggestion->content_item->content_block->section->id,
        content_block => $suggestion->content_item->content_block->id,
        content_item => $suggestion->content_item->id,
        suggestion => $suggestion->id,
        action => $class,
        resume => $suggestion->resume->id,
        instance => $suggestion->resume->instance,
        acting_user => $self->active_user->id,
        old_value => $old_yaml,
        new_value => $ci->serialize_yaml,
    });

    # clear the cache for this instance
    $self->clear_all_cache;

    $romeo->r->content_type('application/x-javascript');
    print $json->encode($json_return);
    return OK;

}

1;