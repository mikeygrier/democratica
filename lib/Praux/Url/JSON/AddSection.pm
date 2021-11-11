package Praux::Url::JSON::AddSection;

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

    # only the owner can create sections.
    unless ($self->active_user->id == $self->resume->praux_user->id) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Only the owner of this resume can create new sections...",
            }
        );
        return OK;
    }

    # section specific infos.
    my $views = $romeo->param('views');
    my $format = $romeo->param('format') || 'generic';

    # create the cb..
    my $sec; 
    
    eval {
        $sec = $self->schema->resultset('Resume::Section')->create(
            {
                resume => $self->resume,
                format => $format,
            }
        );
    };
    
    # set the views if we have any..
    $sec->set_views(split(/,/, $views)) if $views;
    
    if ($sec) {
        # figure out who we are.
        my $class = shift(@uri);

        # take note of what we've done
        my $json_return = $romeo->param('json_return') || {};
        $json_return->{$class} = [] unless $json_return->{$class};
        push(@{$json_return->{$class}}, { message => "Added section block: " . $sec->id });

        # store everything for dispatch.
        $romeo->param('section', $sec->id);
        $romeo->param('json_return', $json_return);
        $romeo->param('format', 'section_header');

        # ok, tell these modules that we will handle sending json back
        $Praux::Url::JSON::ENDPOINTS_PRINT = 0;

        # dispatch to the add content block, so this guy's section_header and content item can be loaded
        $romeo->run_extension('Praux::Url::JSON::AddContentBlock', @uri);
        
        # dump if we're in error.
        if ($json_return->{error}) {
            return OK;
        }
        
        # we have to get our section back.
        $sec = $self->sec($sec->id);
        
        # okay.. now we're gunna add an empty sub content block, if we got here, we should be able to
        # use $section to pull our amazing data back through the cosmos.
        $romeo->param('parent', $sec->header_cb->id);
        $romeo->param('format', $sec->format);
        $romeo->param('body', ''); # null this out.
        
        my $ac_return = $romeo->run_extension('Praux::Url::JSON::AddContentBlock', @uri);
        
        # dump if we're in error.
        if ($json_return->{error}) {
            return OK;
        }
        
        # alright.. if we got here, all we have left to do is render the section and return it
        
        # render this content block.
        $json_return->{rendered_section} = $self->render_section($sec);
        $json_return->{message} = "Section added successfully!";
        
        # clear the cache for this instance
        $self->clear_all_cache;
        
        # turn this back on.
        $Praux::URL::JSON::ENDPOINTS_PRINT = 1;
        
        $self->log_action({
            section => $sec->id,
            action => $class,
            resume => $sec->resume->id,
            instance => $sec->resume->instance,
            acting_user => $self->active_user->id,
        });
        
        $json_return->{general_message} = "Section added successfully!";
        $json_return->{success} = 1;
        $romeo->r->content_type('application/x-javascript');
        print $json->encode($json_return);
        return OK;
    } else {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "We encountered an error while creating this section: $@",
            }
        );
        return OK;
    }
}
1;
