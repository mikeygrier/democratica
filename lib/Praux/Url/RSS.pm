# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::RSS;

use base qw/Praux::Url::Component/;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use XML::RSS;

sub handle_request {
    my ($self, $romeo, @uri) = @_;

	$romeo->r->no_cache(1);
	my $rss = XML::RSS->new(version => '1.0');
	$rss->image(
	    title => 'praux.com',
	    url => 'http://praux.com/img/pc.png',
	    link => 'http://praux.com',
	    width => 100,
	    height => 100,
	    description => "Praux.com - We told you so.",
	);
	
	if ($self->instance eq "www" || $self->instance eq "ssl" || $self->instance eq "") {
        my $rs = $self->schema->resultset('Log')->search( {
            create_time => { '>', (time() - 1209600) },
        }, { order_by => 'create_time DESC' });
    
        if ($rs->count > 0) {        
            $rss->channel(
                title => "Recent Praux.com Activity",
                link => $self->romeo->app_base,
                description => "Site-wide recent updates to resumes hosted by Praux.com",
                dc => {
                    date => $self->format_date_time($rs->first->create_time),
                    subject => "Site-wide recent updates to resumes hosted by Praux.com",
                    creator => 'SysOp@praux.com',
                    publisher => 'SysOp@praux.com',
                    rights => "&copy; " . ((localtime)[5] + 1900) . " Praux.com and its contributors, All rights reserved.",
                    language => $rs->first->resume->default_language,
                },
                syn => {
                    updatePeriod => 'hourly',
                    updateFrequency => 4,
                    updateBase => '2009-01-01T00:00+00:00',
                },
            );
        
            # get the resumes in their order of last edit..
            my @resumes;
            foreach my $result ($rs->all) {
                my $resume = $result->resume;
                my $already_listed;
                foreach my $listed (@resumes) {
                    $already_listed = 1 if $listed->id == $resume->id;
                }
                push(@resumes, $resume) unless $already_listed;
            }
        
            # iterate thru them, summarizing the changes
            foreach my $resume (@resumes) {
                foreach my $summary ($resume->summarize_changes) {
                    $rss->add_item(
                        title => $summary->{title} . " - " . $resume->instance . $self->romeo->c->COOKIE_DOMAIN,
                        link => 'http://' . $resume->instance . $self->romeo->c->COOKIE_DOMAIN,
                        description => "<pre>" . $summary->{description} . "</pre>",
                        dc => {
                            date => $self->format_date_time($summary->{date}),
                            subject => "recent resume updates",
                        },
                    );
                
                    # we're only going to do the most recent resume activity per-resume to keep this rss short & sweet!
                    last;
                }
            }
        } else {
            $romeo->r->content_type('text/html');
            $romeo->render_error("Hmm.. this is weird, I couldn't find any changes for this resume!");
            return OK;
        }
	} elsif ($self->resume) {	
        $rss->channel(
            title => "Recent Updates to " . $self->romeo->instance,
            link => $self->romeo->app_base,
            description => "Updates to " . $self->resume->name . "'s Praux.com resume at " . $self->romeo->instance,
            dc => {
                date => $self->format_date_time($self->resume->changes(undef, { order_by => 'create_time DESC' })->first->create_time),
                subject => "Recent Updates to " . $self->romeo->instance,
                creator => $self->resume->email,
                publisher => $self->resume->email,
                rights => "&copy; " . ((localtime)[5] + 1900) . " " . $self->resume->name,
                language => $self->resume->default_language,
            },
            syn => {
                updatePeriod => 'hourly',
                updateFrequency => 4,
                updateBase => '2009-01-01T00:00+00:00',
            },
        );
	
    	foreach my $summary ($self->resume->summarize_changes) {
            $rss->add_item(
                title => $summary->{title},
                link => $self->romeo->app_base,
                description => "<pre>" . $summary->{description} . "</pre>",
                dc => {
                    date => $self->format_date_time($summary->{date}),
                    subject => "recent resume updates",
                },
            );
    	}	
	} else {
	    $romeo->r->content_type('text/html');
	    $romeo->render_error("You have to visit /rss/ from an existing resume or from the main site!");
	    return OK;
	}

	# 15 minutes of cache!
	$romeo->r->headers_out->set('Cache-Control', 'max-age=' . (15*60));
    $romeo->r->content_type('text/rss+xml;charset=utf-8');
    print $rss->as_string;
    return OK;
}

sub format_date_time {
    my ($self, $time) = @_;

    my @time = gmtime $time;

    return sprintf "%4d-%02d-%02dT%02d:%02dZ",
        $time[5] + 1900, $time[4] + 1, $time[3],
        $time[2], $time[1], $time[0];
}

1;
