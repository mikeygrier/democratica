package Praux::Url::SetDefaultTheme;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

#
# I guess you guys aren't ready for this.. but your kids are gonna love it!
#

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    # if we're not logged in, do nothing
    
    my $resume_id = $romeo->param('resume_id');
    my $view_id = $romeo->param('view_id');
    my $resume_url = $romeo->param('resume_url');
    my $theme_id = $romeo->param('theme_id');
    
    unless ($self->active_user) {
        $romeo->r->content_type('text/html');
        $romeo->render_error("You have to be logged in to set a default theme..");
        return OK;
    }

    # word!
    if (!$self->resume || ($self->instance eq "www" || $self->instance eq "ssl" || $self->instance eq "")) {
        $romeo->r->content_type('text/html');
	    $romeo->render_error("You have to visit /set_default_theme/ from a resume!");
	    return OK;
	}

    # only the owner can touch me like that
    unless ($self->active_user->id == $self->resume->praux_user->id) {
        $romeo->r->content_type('text/html');
        $romeo->render_error("Only the owner of this resume can set the theme... why dont you go get them for me?");
        return OK;
    }
    
    my $theme = $self->theme_by_id($theme_id);
    my $view_obj = $self->schema->resultset('Resume::View')->find({ id => $view_id }) if $view_id;
    
    if (ref($view_obj) && (lc($view_obj->view_name) ne "default" && lc($view_obj->view_name) ne "edit" && lc($view_obj->view_name) ne "all")) {
        my $view_name = $view_obj->view_name;
        $self->resume->views->search(view_name => $view_name)->update(
            {
                default_theme => $theme->id,
            }
        );
    } else {
        my $resume = $self->resume;
        $resume->default_theme($theme_id);
        $resume->update();
    }
    
    # clear the cache for this instance
    $self->clear_all_cache;
    
    my $class = shift(@uri);
    $self->log_action({
        action => $class,
        resume => $self->resume,
        instance => $self->instance,
        acting_user => $self->active_user->id,
    });
    
    $romeo->r->content_type('text/html;charset=utf-8');
    $romeo->r->headers_out->set(Location => $resume_url);
    return REDIRECT;
}
1;
