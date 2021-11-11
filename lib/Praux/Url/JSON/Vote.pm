package Praux::Url::JSON::Vote;

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
    my $vote = $romeo->param('vote');
    
    if ($vote !~ /(?:up|down)/) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Unexpected vote data encountered",
            }
        );
        return OK;
    } else {
        # turn this into the numeric equiv.
        if ($vote eq "up") {
            $vote = 1;
        } else {
            $vote = -1;
        }
    }
    
    if ($cb) {
        my $old_vote = $self->active_user->votes->find({content_block => $cb->id});
        
        # let's get our json return on.
        my $json_return = $romeo->param('json_return') || {};
        my $class = shift(@uri);
        
        if ($old_vote) {
            $old_vote->vote($vote);
            $old_vote->update;
        } else {        
            $self->schema->resultset('User::Vote')->create(
                {
                    content_item => $cb->visible_item($romeo->param('language_context'))->id,
                    content_block => $cb->id,
                    section => $cb->section->id,
                    resume => $cb->resume->id,
                    owner => $self->active_user->id,
                    vote => $vote,
                }
            );
        }
        
        push(@{$json_return->{$class}}, 
            {
                message => "Vote recorded for " . $cb->id,
                html_id => $romeo->param('html_id'),
            }
        );
        
        $json_return->{general_message} = "Vote recorded.  Thank you for voting!";
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
