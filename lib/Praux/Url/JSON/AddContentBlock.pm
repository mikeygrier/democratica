package Praux::Url::JSON::AddContentBlock;

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
                error => "Only the owner of this resume can create new content blocks...",
            }
        );
        return OK;
    }

    # Block Specific Data
    my $section = $romeo->param('section');
    my $parent = defined($romeo->param('parent')) ? $romeo->param('parent') : 0;
    my $views = $romeo->param('views');
    my $format = $romeo->param('format') || 'generic';

    # resolve section or throw up.
    if (!$section) {
        if ($parent && $self->cb($parent)) {
			$section = $self->cb($parent)->section->id;
        } else {
            $romeo->r->content_type('application/x-javascript');
            print $json->encode(
                {
                    success => 0,
                    error => "No section or valid parent supplied, where do you want me to put the content block?",
                }
            );
            return OK;
        }
    }

    # in case we have it -- for daisy chaining
    my $json_return = $romeo->param('json_return') || {};

    # create the cb..
    my $cb; 
    
    eval {
        $cb = $self->schema->resultset('Resume::ContentBlock')->create(
            {
                section => $section,
                parent => $parent,
                format => $format,
                resume => $self->resume->id,
            }
        );
    };

    # set the views if we have any..
    $cb->set_views(split(/,/, $views)) if $views;

    if ($cb) {
        # figure out who we are
        my $class = shift(@uri);
        
        # get out our awesome return
        my $json_return = $romeo->param('json_return') || {};
        $json_return->{$class} = [] unless $json_return->{$class};

        # take note of what we've done
        push(@{$json_return->{$class}}, { message => "Added content block: " . $cb->id });

        # store it up
        $romeo->param('content_block', $cb->id);
        $romeo->param('visible', 1); # the first one's always visible
        $romeo->param('json_return', $json_return);
        
        $self->log_action({
            section => $cb->section->id,
            content_block => $cb->id,
            action => $class,
            resume => $cb->resume->id,
            instance => $cb->resume->instance,
            acting_user => $self->active_user->id,
        });
        
        # clear the cache for this instance
        $self->clear_all_cache;

        # dispatch to the add content item, so this guy's content item can be added
        return $romeo->run_extension('Praux::Url::JSON::AddContentItem', @uri);
    } else {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Error creating content block: $@",
            }
        );
    }
    return OK;
}

1;
