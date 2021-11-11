#!/usr/bin/env perl

use Praux;
use LWP::Simple;
my $praux = new Praux;

foreach my $resume ($praux->schema->resultset('Resume')->all) {
    if ($resume->completeness >= 80) {
        print "[" . $resume->instance . "]\n";
        # google
        get("http://google.com/ping?sitemap=http://" . $resume->instance . ".praux.com/sitemap.xml");
        print "Google!\n";

        # yahoo
        get("http://search.yahooapis.com/SiteExplorerService/V1/updateNotification?appid=YahooDemo&url=" . $resume->instance . ".praux.com/sitemap.xml");
        print "Yahoo!\n";

        # bing
        get("http://www.bing.com/webmaster/ping.aspx?siteMap=http://" . $resume->instance . ".praux.com/sitemap.xml");
        print "Bing!\n";

        print "\n";
    }
}

