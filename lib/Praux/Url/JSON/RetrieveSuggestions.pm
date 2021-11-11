package Praux::Url::JSON::RetrieveSuggestions;

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
    unless ($romeo->param_was_sent('content_block')) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Must specify content_block in retrieve_suggestions request.",
            }
        );
        return OK;
    }
    
    # resolve the block to an item...
    my $cb = $self->cb($romeo->param('content_block'));
 
    # check edit access
    my $can_view = 0;
    if ($self->active_user->id == $cb->resume->praux_user->id) {
        # resume owners can edit anything in their resume (looks like i have to bubble way up for security)
        $can_view = 1;
    }

    unless ($can_view) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "You do not have access to view this content.",
            }
        );
        return OK;
    }
    
    # get the class..
    my $class = shift(@uri);
    
    # in case we have it -- for daisy chaining
    my $json_return = $romeo->param('json_return') || {};
    
    # initialize "our" arrayref.  we can not call ourselves, we have to take care 
    # of all our work, is that too much to ask?
    $json_return->{$class} = [] unless $json_return->{$class};
    
    # pull this from our POST now..
    my $suggested_attribute = $romeo->param('suggested_attribute');
    
    # get all the suggestions for this attribute
    my $vi = $cb->visible_item($romeo->param('language_context'));
    foreach my $suggestion ($vi->suggestions->search({ suggested_attribute => $suggested_attribute, used => 0 })) {
        push(@{$json_return->{$class}}, 
            {
                suggested_value => $suggestion->suggested_value,
                create_time => $self->pretty_date($suggestion->create_time),
                submitter_email => $suggestion->submitter->email,
                submitter_common_name => $suggestion->submitter->common_name,
                suggestion => $suggestion->id,
                html_id => $cb->id . '-' . $suggested_attribute,
            }
        );
    }
    
    # we're an endpoint.
    if ($Praux::Url::JSON::ENDPOINTS_PRINT) {
        $json_return->{general_message} = "Suggestions retrieved successfully!";
        $json_return->{success} = 1;
        $romeo->r->content_type('application/x-javascript');
        print $json->encode($json_return);
    }
    
    return OK;
}


1;
