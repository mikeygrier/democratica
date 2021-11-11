# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::Sitemap;

use base qw/Praux::Url::Component/;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

sub handle_request {
    my ($self, $romeo, @uri) = @_;
	
	# 15 minutes of cache!
	$romeo->r->headers_out->set('Cache-Control', 'max-age=' . (15*60));
    $romeo->r->content_type('text/xml;charset=utf-8');
    
    # XML Definition & Sitemap Tag
    print '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
    print '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' . "\n";
    
    if ($self->resume) {
        # one resume sitemap..
        my $resume = $self->resume;
        
        # implement caching!
        my $cache_key = "SITEMAP/" . $resume->instance;
        $cache_key .= "/dev" if $self->is_dev;
        my $content;
        unless ($content = $self->memd->get($cache_key)) {            
            my $ri = $self->resume_info($resume);
    
            my $title_href = "http://$ri->{resume}/";
            if ($ri->{recent_title} eq "Editor In Chief") {
                $title_href .= "resume.html";
                $ri->{recent_title} = "An Excellent Candidate";
            } else {
                $title_href .= join('-', map { lc($_) } split(/\s+/, $ri->{recent_title})) . ".html";
            }
    
            # first do the title href...
            $content .= print_url($title_href, $resume->modify_time, "monthly", "0.8"); 
    
            # now the defaults..
            foreach my $file (qw/html pdf doc txt odt rtf/) {
                $content .= print_url("http://$ri->{resume}/resume.$file", $resume->modify_time, "monthly", "0.5");
            }

            # all views in all languages
            foreach my $lang (@{$ri->{languages}}) {
                $content .= print_url("http://$ri->{resume}/default/$lang/", $resume->modify_time, "monthly", "0.5");
                foreach my $file (qw/html pdf doc txt odt rtf/) {
                    $content .= print_url("http://$ri->{resume}/default/$lang/resume.$file", $resume->modify_time, "monthly", "0.5");
                }
                foreach my $view (@{$ri->{views}}) {
                    unless ($view eq "default") {
                        $content .= print_url("http://$ri->{resume}/$view/$lang/", $resume->modify_time, "monthly", "0.5");
                        foreach my $file (qw/html pdf doc txt odt rtf/) {
                            $content .= print_url("http://$ri->{resume}/$view/$lang/resume.$file", $resume->modify_time, "monthly", "0.5");
                        }
                    }
                }
            }
    
            # important links!
            $content .= print_url("http://$ri->{resume}/important_links/", $resume->modify_time, "monthly", "0.8");   
            $self->memd->set($cache_key, $content, 86000);
        }
        
        print $content;
    } else {    
        # global sitemap!
        # implement caching!
        my $cache_key = "SITEMAP/GLOBAL";
        $cache_key .= "/dev" if $self->is_dev;
        my $content;
        
        unless ($content = $self->memd->get($cache_key)) {  
            $content .= print_url("http://praux.com/page/master_list/", time, "always", "0.9");
            $content .= print_url("http://praux.com/page/content_search/", time, "always", "0.5");
            $content .= print_url("http://praux.com/page/privacy/", time, "monthly", "0.5");
            $content .= print_url("http://praux.com/page/tos/", time, "monthly", "0.5");
            $content .= print_url("http://praux.com/", time, "always", "0.9");
            $content .= print_url("http://help.praux.com/", time, "weekly", "0.9");
            $content .= print_url("http://help.praux.com/projects/praux/wiki/PrauxfessorsHandbook", time, "monthly", "0.9");
        
            foreach my $resume ($self->schema->resultset('Resume')->all) {
                next unless $resume->completeness >= 80;
                my $ri = $self->resume_info($resume);
        
                my $title_href = "http://$ri->{resume}/";
                if ($ri->{recent_title} eq "Editor In Chief") {
                    $title_href .= "resume.html";
                    $ri->{recent_title} = "An Excellent Candidate";
                } else {
                    $title_href .= join('-', map { lc($_) } split(/\s+/, $ri->{recent_title})) . ".html";
                }
        
                # first do the title href...
                $content .= print_url($title_href, $resume->modify_time, "monthly", "0.8");
        
                # now the defaults..
                foreach my $file (qw/html pdf doc txt odt rtf/) {
                    $content .= print_url("http://$ri->{resume}/resume.$file", $resume->modify_time, "monthly", "0.5");
                }

                # all views in all languages
                foreach my $lang (@{$ri->{languages}}) {
                    foreach my $file (qw/html pdf doc txt odt rtf/) {
                        $content .= print_url("http://$ri->{resume}/default/$lang/resume.$file", $resume->modify_time, "monthly", "0.5");
                    }
                    foreach my $view (@{$ri->{views}}) {
                        unless ($view eq "default") {
                            foreach my $file (qw/html pdf doc txt odt rtf/) {
                                $content .= print_url("http://$ri->{resume}/$view/$lang/resume.$file", $resume->modify_time, "monthly", "0.5");
                            }
                        }
                    }
                }
        
                # important links!
                $content .= print_url("http://$ri->{resume}/important_links/", $resume->modify_time, "monthly", "0.8");
            }
            $self->memd->set($cache_key, $content, 86000);
        }
        print $content;
    }
    
    print '</urlset>' . "\n";
    return OK;
}

sub print_url {
    my ($url, $lastmod, $changefreq, $priority) = @_;

    # ok.. unless we have something..
    return undef unless $url;

    # set defaults
    $changefreq = "monthly" unless $changefreq;
    $priority = "0.5" unless $priority;
    
    # format teh URL!
    $url =~ s/\&/\&amp;/g;
    $url =~ s/'/\&apos;/g;
    $url =~ s/"/\&quot;/g;
    $url =~ s/\>/\&gt;/g;
    $url =~ s/\</\&lt;/g;
    
    # format lastmod...
    my @t = gmtime($lastmod);
    $lastmod = sprintf('%4d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]);
    
    my $rval;
    
    $rval .= "  <url>\n";
    $rval .= "    <loc>$url</loc>\n";
    $rval .= "    <lastmod>$lastmod</lastmod>\n";
    $rval .= "    <changefreq>$changefreq</changefreq>\n";
    $rval .= "    <priority>$priority</priority>\n";
    $rval .= "  </url>\n";
    
    return $rval;
}

1;
