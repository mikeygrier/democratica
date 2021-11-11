# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::PDFPage;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    my $page = $uri[1];

	$romeo->r->no_cache(1);

    my $host = $romeo->r->hostname;
    
    my $cache_key = "$host/PDFPage/$page";
    
    my $pdfpage;
    unless ($pdfpage = $self->memd->get($cache_key)) {
        my $pdf_url = "http://$host/page/$page/";

        open(WKHTML2PDF, '-|', '/usr/local/bin/wkhtmltopdf -B 0 -T 0 -L 0 -R 0 -s A4 -nq ' . $pdf_url . " -");
        {
            local $/;
            $pdfpage = <WKHTML2PDF>;
        }
        close(WKHTML2PDF);
        
        $self->memd->set($cache_key, $pdfpage, 3600) or warn "Error caching: $@\n";
    }
    
    $self->romeo->r->content_type('application/pdf');
    print $pdfpage;
    return OK;
}

1;
