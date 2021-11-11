package Praux::Url::JSON::GetContentBlock;

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
    
    my $vi = $cb->visible_item($romeo->param('language'));
    
    if ($vi) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 1,
                date_range => $vi->date_range,
                content_item => $vi->id,
                content_block => $cb->id,
                organization => $vi->organization,
                locality => $vi->locality,
                role => $vi->role,
                instructor => $vi->instructor,
                title => $vi->title,
                body => $vi->body,
                visible => $vi->visible,
                language => $vi->language,
            }
        );
    } else {
        print $json->encode(
            success => 0,
            error => "Could not find visible item in language " . $romeo->param('language'),
        );
    }
    
    return OK;
}


1;