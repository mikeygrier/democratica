package Praux::Url::JSON::EditContentItem;

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

    # ok we only NEED one field.. lets just do something more sane then that array crap
    unless ($romeo->param_was_sent('content_block') || $romeo->param_was_sent('content_item')) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Must specify either content_block or content_item in edit_content_item request.",
            }
        );
        return OK;
    }

    my @anticipated = qw/ 
        date_range content_item organization locality 
        role instructor title body visible language
    /;

    # get everything we're anticipating getting...  don't viv that damn fucking shitfaced
    # garbage hash.  thanks.
    my %values;
    foreach my $key (@anticipated) {
        if ($romeo->param_was_sent($key)) {
            $values{$key} = $romeo->param($key);
        }
    }

    my $cb;
    # resolve the block to an item...
    if (my $cbid = $romeo->param('content_block')) {
        $cb = $self->cb($cbid);
    } else {
        warn "Couldn't find content block?";
    }

    # get the content item from the block or from the post arguments.
    my $ci = $cb ? $cb->visible_item($values{language}) : $self->ci($values{content_item});
    
    # or make the ci, in the event that it doesn't exist.
    unless ($ci) {
        # get the submitter id...
        $values{submitter} = $self->active_user->id;
        $values{visible} = 1;
        $values{content_block} = $cb->id;
        $values{resume} = $cb->resume->id;

        # create the ci..
        eval {
            $ci = $self->schema->resultset('Resume::ContentItem')->create(\%values);
        };
        
        if (my $error = $@) {
            $romeo->r->content_type('application/x-javascript');
            print $json->encode(
                {
                    success => 0,
                    error => "Error creating content item: $error",
                }
            );
            return OK;
        }
    }
    
    # check edit access
    my $can_edit = 0;
    if ($self->active_user->id == $ci->resume->praux_user->id) {
        # resume owners can edit anything in their resume (looks like i have to bubble way up for security)
        $can_edit = 1;
    } elsif ($ci->submitter->id == $self->active_user->id && $ci->content_block->visible == 0) {
        # submitter can edit their own submissions if they're not currently visible, and they still
        # own it
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

    # in case we have it -- for daisy chaining
    my $json_return = $romeo->param('json_return') || {};
    my $class = shift(@uri);
    
    # initialize "our" arrayref.  we can not call ourselves, we have to take care 
    # of all our work, is that too much to ask?
    $json_return->{$class} = [] unless $json_return->{$class};
    
    my $old_yaml = $ci->serialize_yaml;
    
    foreach my $key (keys %values) {
        $ci->$key($values{$key});
        
        eval {
            $ci->update();
        };

        # throw back the error
        if (my $error = $@) {
            $romeo->r->content_type('application/x-javascript');
            print $json->encode(
                {
                    success => 0,
                    error => $error,
                }
            );
            return OK;
        }
        
        unless ($key eq "language") {
            push(@{$json_return->{$class}}, 
                {
                    message => "Updated field $key",
                    html_id => $ci->content_block->id . "-$key",
                    block_id => $ci->content_block->id,
                    item_id => $ci->id,
                    display_value => ($values{$key} or $self->empty_labels->{$ci->content_block->format}->{$key}),
                    rendered_block => ($key eq "body" && $ci->content_block->format eq "generic") ? $self->render_generic_spanonly($ci->content_block) : undef,
                }
            );
        }
    }

    $self->log_action({
        section => $ci->content_block->section->id,
        content_block => $ci->content_block->id,
        content_item => $ci->id,
        action => $class,
        resume => $ci->resume->id,
        instance => $ci->resume->instance,
        acting_user => $self->active_user->id,
        new_value => $ci->serialize_yaml,
        old_value => $old_yaml,
    });

    # clear the cache for this instance
    $self->clear_all_cache;

    if ($ci) {
        # we're an endpoint.
        if ($Praux::Url::JSON::ENDPOINTS_PRINT) {
            $json_return->{general_message} = "Content item updated successfully!";
            $json_return->{success} = 1;
            $romeo->r->content_type('application/x-javascript');
            print $json->encode($json_return);
        }
    } else {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Error updating content item: $@",
            }
        );
    }
    return OK;
}

1;