package Praux::Url::UploadTheme;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Upload;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

#
# kk .. this is a blues riff in b, watch me for the changes...
# and try to keep up. 
#

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    
    # if we're not logged in, do nothing
    unless ($self->active_user) {
        $romeo->r->content_type('text/html');
        $romeo->render_error("You have to be logged in to upload a theme!");
        return OK;
    }
    
    if (!$self->resume || ($self->instance eq "www" || $self->instance eq "ssl" || $self->instance eq "")) {
        $romeo->r->content_type('text/html');
	    $romeo->render_error("You have to visit /upload_theme/ from a resume!");
	    return OK;
	}
    
    my ($upload) = $romeo->{apr}->upload('theme_file');
    my $theme_name = $romeo->param('theme_name');
    my $resume_url = $romeo->param('resume_url');
    my $resume_id = $romeo->param('resume_id');
    my $view_id = $romeo->param('view_id');
    
    if ($theme_name && $upload) {
        my $theme_uuid = $self->new_uuid;
        my $theme_deploy_dir = $romeo->c->PRAUX_THEME_DIR . "/" . $theme_uuid . "/";
        my $theme_temp_file = "/tmp/" . $theme_uuid . ".zip";

        open(TEMPFILE, '>', $theme_temp_file) or die "Error opening temp file '$theme_temp_file': $!\n";
        my $fh = $upload->fh();
        while (my $td = <$fh>) {
            print TEMPFILE $td;
        }
        close(TEMPFILE);

        system("/usr/bin/unzip -qq $theme_temp_file -d $theme_deploy_dir");
        
        my $data = {
            deploy_uuid => $theme_uuid,
            theme_name => $theme_name,
            owner => $self->active_user->id,
            deploy_type => 'local',
        };
        
        if ($self->active_user->id == $self->resume->praux_user->id) {
            $data->{resume} = $self->resume->id;
        }
        
        my $rs = $self->schema->resultset('Resume::Theme')->search(
            {
                theme_name => $theme_name,
                owner => $self->active_user->id,
                resume => $self->resume->id,
            }
        );

        if ($rs->count > 0) {
            foreach my $theme ($rs->all) {
                # get rid of the old dir...
                if ($theme->deploy_uuid && -d $romeo->c->PRAUX_THEME_DIR . "/" . $theme->deploy_uuid . "/") {
                    system("/bin/rm -r " . $romeo->c->PRAUX_THEME_DIR . "/" . $theme->deploy_uuid . "/");
                    $theme->delete;
                }
            }
        }

        my $theme = $self->schema->resultset('Resume::Theme')->create($data);

        my $class = shift(@uri);
        $self->log_action({
            action => $class,
            resume => $self->resume->id,
            instance => $self->instance,
            acting_user => $self->active_user->id,
        });

        $romeo->r->content_type('text/html;charset=utf-8');
        # if we're eligable to set this theme as the default here, lets keep rollin thru!
        if ($self->active_user->id == $self->resume->praux_user->id) {
            $romeo->r->headers_out->set(Location => "/set_default_theme/?resume_url=" . $resume_url . "&resume_id=" . 
                $resume_id . "&view_id=" . $view_id . "&theme_id=" . $theme->id);
        } else {
            $romeo->r->headers_out->set(Location => $resume_url);
        }
        return REDIRECT;

    } else {
        $romeo->r->content_type('text/html;charset=utf-8');
        $romeo->render_error("Theme file and theme name are required to upload a theme!");
    }
    
    return OK;
}
1;
