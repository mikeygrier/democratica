package Praux::Url::ProvisionerEmblem;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::SubRequest;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    
    # a little rework ;P
    my $resume;
    unless ($resume = $self->resume) {
        my $referrer = $self->romeo->r->headers_in->get('Referer');
        if ($referrer =~ /([\w\-\.]+)\/$/) {
            $resume = $self->resume_by_instance($1);
        }
    }
    
    $romeo->r->content_type('image/png');
    if ($resume) {
        if (my $emblem = $resume->praux_user->provisioner->emblem) {
            print $emblem;
        } else {
            $romeo->r->internal_redirect('/img/pc.png');
        }
    } else {
        $romeo->r->internal_redirect("/img/pc.png");
    }
    
    return OK;
}

1;
