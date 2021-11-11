# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::MailMask;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Praux::Util::Zimbra;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    my $page = $uri[1];

    my ($enable_flow) = $romeo->param('enable_flow');
    my ($show_mask) = $romeo->param('show_mask');
    my $back = $romeo->param('back');
    
    if (my $user = $self->active_user) {
        if (my $resume = $user->resume) {
            my $zimbra = Praux::Util::Zimbra->new(
                resume => $resume,
            );
            
            if ($enable_flow == 1) {
                $zimbra->enable_mailmask;
            } elsif (defined $enable_flow && $enable_flow == 0) {
                $zimbra->disable_mailmask;
            }
            
            if ($show_mask == 1) {
                $user->preference('com.praux.showmailmask', 1);
                $self->clear_all_cache;
            } elsif (defined $show_mask && $show_mask == 0) {
                $user->preference('com.praux.showmailmask', 0);
                $self->clear_all_cache;
            }
        }
    }
    
    $romeo->r->headers_out->set(Location => $back);
    return REDIRECT;
}

1;
