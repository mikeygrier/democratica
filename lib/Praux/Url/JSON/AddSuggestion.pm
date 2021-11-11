package Praux::Url::JSON::AddSuggestion;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use Mail::Sender;
use JSON;

$Mail::Sender::NO_X_MAILER = 1;

my $mailer = Mail::Sender->new(
    {    
        smtp        =>      'mail.mg2.org',
        from        =>      'admin@praux.com',
        headers     =>      {
            'X-Mailer'      =>      'Praux v0.05',
        }
    }
);

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
                error => "Must specify content_block in add_suggestion request.",
            }
        );
        return OK;
    }

    my $cb = $self->cb($romeo->param('content_block'));
    my $vi = $cb->visible_item($romeo->param('language_context'));
    my $suggested_attribute = $romeo->param('suggested_attribute');
    my $suggested_value = $romeo->param('suggested_value');
    
    # ok so we're adding a suggestion for this visible item.
    
    if ($vi) {
        # figure out who we are
        my $class = shift(@uri);
        
        # in case we have it -- for daisy chaining
        my $json_return = $romeo->param('json_return') || {};

        # take note of what we've done in this $class
        $json_return->{$class} = [] unless $json_return->{$class};
        
        # ok we're logged in, and we have a visible item.  i think we're good.
        my $suggestion = $vi->suggestions->create(
            {
                suggested_attribute => $suggested_attribute,
                suggested_value => $suggested_value,
                submitter => $self->active_user->id,
                resume => $self->resume->id,
            }
        );
        
        push(@{$json_return->{$class}}, { 
            message => "Added suggestion: " . $suggestion->id,
            html_id => $romeo->param('html_id'),
        });
        
        $self->send_suggestion_email($self->active_user, $cb->resume->praux_user, $suggestion);
        
        $self->log_action({
            section => $suggestion->content_item->content_block->section->id,
            content_block => $suggestion->content_item->content_block->id,
            content_item => $suggestion->content_item->id,
            suggestion => $suggestion->id,
            action => $class,
            resume => $suggestion->resume->id,
            instance => $suggestion->resume->instance,
            acting_user => $self->active_user->id,
        });
        
        # we're an endpoint.
        if ($Praux::Url::JSON::ENDPOINTS_PRINT) {
            $json_return->{general_message} = "Suggestion added successfully!";
            $json_return->{success} = 1;
            $romeo->r->content_type('application/x-javascript');
            print $json->encode($json_return);
            return OK;
        }
    } else {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "No visible item found for content block.",
            }
        );
        return OK;
    }
}

sub send_suggestion_email {
    my ($self, $source_user, $target_user, $suggestion) = @_;

    # get the body!
    my $body;
    $self->romeo->template->process($self->romeo->theme . "/" . 'new_suggestion_email.htmlt', {
        src => $source_user, 
        tgt => $target_user, 
        sug => $suggestion, 
        self => $self
    }, \$body);

    my $result = $mailer->MailMsg(
        {
            to => $target_user->email,
            from => $source_user->common_name . "<suggestions\@praux.com>",
            subject => '[praux] New Resume Suggestion From ' . $source_user->common_name,
            msg => $body,
        }
    );

    if (ref($result) eq "Mail::Sender") {
        # success!
        return 1;
    } else {
        # failure!
        return undef;
    }
}
1;
