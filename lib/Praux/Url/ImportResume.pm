package Praux::Url::ImportResume;

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
        $romeo->r->content_type('text/html;charset=utf-8');
        $romeo->render_error("You have to be logged in to import a resume!");
        return OK;
    }
    
    if (!$self->resume || ($self->instance eq "www" || $self->instance eq "ssl" || $self->instance eq "")) {
        $romeo->r->content_type('text/html;charset=utf-8');
	    $romeo->render_error("You have to run /import_resume/ from a resume!");
	    return OK;
	}
    
    my ($upload) = $romeo->{apr}->upload('resume_file');
    
    if ($self->active_user->id == $self->resume->praux_user->id && $upload) {
        my $fh = $upload->fh();
        my $yaml;
        {
            local $/;
            $yaml = <$fh>;
        }
        
        unless ($yaml =~ /^---/) {
            $romeo->r->content_type('text/html;charset=utf-8');
            $romeo->render_error("Invalid file format (Not YAML)");
            return OK;
        }
        
        eval {
            $self->import_yaml_resume($yaml, $self->instance);
        };
        
        if ($@) {
            $romeo->r->content_type('text/html;charset=utf-8');
            $romeo->render_error("Error importing resume: $@, $!");
            return OK;
        }
        
        # clear the cache for this instance
        $self->clear_all_cache;
        
        $romeo->r->headers_out->set(Location => "/");
        return REDIRECT;

    } else {
        $romeo->r->content_type('text/html;charset=utf-8');
        $romeo->render_error("I didn't see a resume to import!  Try uploading one?");
    }
    return OK;
}

1;
