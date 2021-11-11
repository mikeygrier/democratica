package Praux::Url::JSON::Comment;

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
    
    my $cb = $self->cb($romeo->param('content_block'));
    my $comment = $romeo->param('comment');
    
    if ($cb) {
        # let's get our json return on.
        my $json_return = $romeo->param('json_return') || {};
        my $class = shift(@uri);
         
        $self->schema->resultset('Resume::ContentItem::Comment')->create(
            {
                content_item => $cb->visible_item($romeo->param('language_context'))->id,
                content_block => $cb->id,
                submitter => $self->active_user->id,
                section => $cb->section->id,
                resume => $cb->resume->id,
                owner => $cb->resume->praux_user->id,
                comment => $comment,
            }
        );
    
        push(@{$json_return->{$class}}, 
            {
                message => "Comment recorded for " . $cb->id,
                html_id => $romeo->param('html_id'),
            }
        );
        
        $self->log_action({
            section => $cb->section->id,
            content_item => $cb->visible_item($romeo->param('language_context'))->id,
            content_block => $cb->id,
            action => $class,
            resume => $cb->resume->id,
            instance => $cb->resume->instance,
            acting_user => $self->active_user->id,
        });
        
        $json_return->{general_message} = "Comment recorded.  Thank you for your input!";
        $json_return->{success} = 1;
        $romeo->r->content_type('application/x-javascript');
        print $json->encode($json_return);
        return OK;
        
    } else {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Content block not found...",
            }
        );
        return OK;
    }
}
1;
