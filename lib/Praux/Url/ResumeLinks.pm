# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::ResumeLinks;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

sub handle_request {
    my ($self, $romeo, @uri) = @_;
	$romeo->r->no_cache(1);
	
	my $resume = $self->resume;
	
    # get the views
    my $vh = {};
    foreach my $view ($resume->views) {
        $vh->{$view->view_name}++;
    }
    
    # get the languages
    my $lh = {};
    foreach my $ci ($resume->content_items) {
        $lh->{$ci->language}++;
    }
    
    # the available views, sorted alphabetically
    my @views = sort { $a cmp $b } keys %$vh;
    
    # the available languages, sorted alphabetically
    my @langs = sort { $a cmp $b } keys %$lh;
    
    my $ri = {
        views => \@views,
        languages => \@langs,
    };
    
	
    $romeo->r->content_type('text/html;charset=utf-8');
    $self->render_page('resume_links', { ri => $ri });
    return OK;
}

1;
