# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::Atom;

use base qw/Praux::Url::Component/;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use XML::Atom::SimpleFeed;

sub handle_request {
    my ($self, $romeo, @uri) = @_;

	$romeo->r->no_cache(1);
	
	if (!$self->resume || ($self->instance eq "www" || $self->instance eq "ssl" || $self->instance eq "")) {
	    $romeo->r->content_type('text/html');
	    $romeo->render_error("You have to visit /rss/ from a resume!");
	    return OK;
	} else {	
    	my $atom = XML::Atom::SimpleFeed->new(
            title => "Recent Updates to " . $self->romeo->instance,
            link => $self->romeo->app_base,
            link => { rel => 'self', href => $self->romeo->app_base . "/atom/" },
            updated => $self->format_date_time($self->resume->changes(undef, { order_by => 'create_time DESC' })->first->create_time),
            author => $self->resume->name . "<" . $self->resume->email . ">",
    	);
	
    	foreach my $summary ($self->resume->summarize_changes) {
    	    $atom->add_entry(
    	        title => $summary->{title},
    	        link => $self->romeo->app_base,
    	        summary => "<pre>" . $summary->{description} . "</pre>",
    	        updated => $self->format_date_time($summary->{date}),
    	        category => "Recent Resume Updates",
    	    );
    	}
	
    	# 15 minutes of cache!
    	$romeo->r->headers_out->set('Cache-Control', 'max-age=' . (15*60));
        $romeo->r->content_type('text/atom+xml;charset=utf-8');
        $atom->print;
        return OK;
    }
}

sub format_date_time {
    my ($self, $time) = @_;

    my @time = gmtime $time;

    return sprintf "%4d-%02d-%02dT%02d:%02dZ",
        $time[5] + 1900, $time[4] + 1, $time[3],
        $time[2], $time[1], $time[0];
}

1;
