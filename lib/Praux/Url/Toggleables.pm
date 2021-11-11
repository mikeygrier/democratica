package Praux::Url::Toggleables;

@ISA = ('Praux::Url::Component');

use Mail::Sender;
use Praux::Url::Component;
use Praux::Util::Zimbra;
use Apache2::Const qw/:common/;
use Apache2::Util qw/ht_time/;
use Digest::MD5 qw/md5_hex/;
use Carp;

sub handle_request {
    my ($self, $romeo, @args) = @_;

    if (!$self->resume) {
        $romeo->r->content_type('text/html;charset=utf-8');
        $romeo->render_error("This resume doesn't exist yet!  You can't edit it!");
        return OK;
    }

    if (!$self->active_user || ($self->resume->praux_user->id != $self->active_user->id)) {
        $romeo->r->content_type('text/html;charset=utf-8');
        $romeo->render_error('Access Denied -- You do not own this resume, or have not created this resume!');
        return OK;
    }

    my $resume = $self->resume;
    
    my $zimbra = Praux::Util::Zimbra->new(
        resume => $resume,
    );

    $romeo->r->no_cache(1);
    $romeo->r->content_type('text/html;charset=utf-8');
    $self->render_page('toggleables', {mailmask_enabled => $zimbra->mailmask_enabled});
    
    return OK;
}

1;
