# $Id: JSON.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::JSON;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use JSON;

my $json = new JSON;

our $ENDPOINTS_PRINT = 1;

my %json_map = (
    # content block management
    add_content_block => 'Praux::Url::JSON::AddContentBlock',
    edit_content_block => 'Praux::Url::JSON::EditContentBlock',
    remove_content_block => 'Praux::Url::JSON::RemoveContentBlock',
    set_block_order => 'Praux::Url::JSON::SetBlockOrder',
    get_content_block => 'Praux::Url::JSON::GetContentBlock',
    
    # content item management
    add_content_item => 'Praux::Url::JSON::AddContentItem',
    edit_content_item => 'Praux::Url::JSON::EditContentItem',
    
    # section management
    add_section => 'Praux::Url::JSON::AddSection',
    set_section_order => 'Praux::Url::JSON::SetSectionOrder',
    
    # views
    get_views => 'Praux::Url::JSON::GetViews',
    set_views => 'Praux::Url::JSON::SetViews',
    
    # suggestion handlers
    add_suggestion => 'Praux::Url::JSON::AddSuggestion',
    retrieve_suggestions => 'Praux::Url::JSON::RetrieveSuggestions',
    remove_suggestion => 'Praux::Url::JSON::RemoveSuggestion',
    set_suggestion => 'Praux::Url::JSON::SetSuggestion',
    
    # generic
    vote => 'Praux::Url::JSON::Vote',
    comment => 'Praux::Url::JSON::Comment',
    
    availability_check => 'Praux::Url::JSON::AvailabilityCheck',
);

sub handle_request {
    my ($self, $romeo, @uri) = @_;

    my ($this, $function) = (shift(@uri), shift(@uri));

    my $rval;

    if (exists($json_map{$function})) {
        $romeo->param('dispatched_from', $function);
        $rval = $self->romeo->run_extension($json_map{$function}, @uri);
    } else {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Praux does not know about whatever it is you're trying to do. ($function)",
            }
        );
        $rval = OK;
    }
    
    # reset this after every request.. in case i forget.
    $ENDPOINTS_PRINT = 1;
    
    return $rval;
}

1;
