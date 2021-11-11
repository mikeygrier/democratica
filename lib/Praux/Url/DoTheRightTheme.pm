# $Id: DoTheRightTheme.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::DoTheRightTheme;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::SubRequest;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

# /dtrt/<uuid>/
# /dtrt/theme_name/

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    my $theme_name = $uri[1];
    
    my $location = "/themes";
    
    # ok, if the "theme name" looks like a uuid, that's what we're going to do
    if ($theme_name =~ /^[a-z0-9\-]{36}$/) {
        $location .= "/$theme_name"
    } else {
        # resolve the uuid!
        if ($self->active_user) {
            my $user_theme = $self->schema->resultset('Resume::Theme')->search(
                {
                    owner => $self->active_user->id,
                    theme_name => $theme_name,
                }
            )->first;
            
            if ($user_theme) {
                $location .= "/" . $user_theme->deploy_uuid;
                $romeo->r->internal_redirect($location . "/" . join('/', @uri[2..$#uri]));
                return OK;
            }
        }
        
        my $resume_theme = $self->schema->resultset('Resume::Theme')->search(
            {
                resume => $self->resume->id,
                theme_name => $theme_name,
            }
        )->first;
        
        if ($resume_theme) {
            $location .= "/" . $resume_theme->deploy_uuid;
        } elsif (my $default_theme = $self->resume->default_theme) {
            $location .= "/" . $default_theme->deploy_uuid;
        }
        
    }
    
    # redirect!
    $romeo->r->internal_redirect($location . "/" . join('/', @uri[2..$#uri]));
    return OK;
}

1;
