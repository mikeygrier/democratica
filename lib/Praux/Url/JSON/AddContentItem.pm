package Praux::Url::JSON::AddContentItem;

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

    # this is a submit...
    my @anticipated = qw/
        date_range content_block organization locality
        role instructor title body visible language
    /;
    my @required = qw/
        content_block language
    /;

    # get everything we're anticipating getting...
    my %values = map { $_ => $romeo->param($_) || undef } @anticipated;

    foreach my $var (@required) {
        unless (defined $values{$var}) {
            $romeo->r->content_type('application/x-javascript');
            print $json->encode(
                {
                    success => 0,
                    error => "Required element $var not found.",
                }
            );
            return OK;
        }
    }

    # get the submitter id...
    $values{submitter} = $self->active_user->id;

    my $cb;
    # resolve the block to an item...
    if (my $cbid = $romeo->param('content_block')) {
        $cb = $self->cb($cbid);
    } else {
        warn "Couldn't find content block?";
    }
    
    # visible is always no if the logged in user doesn't own this content block.
    if ($cb->section->resume->praux_user->id != $self->active_user->id) {
        $values{visible} = 0;
    } else {
        # just translate undef into zero here if needed.
        $values{visible} = $values{visible} ? $values{visible} : 0;
    }

    $values{resume} = $cb->resume->id;

    # create the ci..
    my $ci; 
    
    eval {
        $ci = $self->schema->resultset('Resume::ContentItem')->create(\%values);
    };

    if ($ci) {
        # figure out who we are
        my $class = shift(@uri);
        
        # in case we have it -- for daisy chaining
        my $json_return = $romeo->param('json_return') || {};

        if (exists($values{'language'})) {
            $self->{lang} = $values{'language'};
            $self->romeo->param('language_context', $values{'language'});
        }

        my $setval = 'unknown';
        foreach my $key (keys %values) {
            next if $key eq "visible";
            next if $key eq "submitter";
            next if $key eq "content_block";
            next if $key eq "language";
            next if $key eq "resume";
            if ($values{$key}) {
                $setval = $key;
            }
        }

        # take note of what we've done
        $json_return->{$class} = [] unless $json_return->{$class};
        push(@{$json_return->{$class}}, { 
            message => "Added content item: " . $ci->id,
            html_id => $ci->content_block->id . "-$setval",
        });
        
        # render this content block.
        $json_return->{rendered_block} = $self->render_content_block($ci->content_block) unless $ci->content_block->format eq "section_header";
        
        # clear the cache for this instance
        $self->clear_all_cache;
        
        $self->log_action({
            section => $ci->content_block->section->id,
            content_block => $ci->content_block->id,
            content_item => $ci->id,
            action => $class,
            resume => $ci->content_block->section->resume->id,
            instance => $ci->resume->instance,
            acting_user => $self->active_user->id,
            new_value => $ci->serialize_yaml,
        });
        
        # we're an endpoint.
        if ($Praux::Url::JSON::ENDPOINTS_PRINT) {
            $json_return->{general_message} = "Content item added successfully!";
            $json_return->{success} = 1;
            $romeo->r->content_type('application/x-javascript');
            print $json->encode($json_return);
        }
    } else {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Error creating content item: $@",
            }
        );
    }
    return OK;
}

1;
