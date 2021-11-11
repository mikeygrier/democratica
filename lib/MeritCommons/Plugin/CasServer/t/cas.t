#    MeritCommons Portal
#    Copyright 2013 Wayne State University
#    All Rights Reserved

use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use Env qw(meritcommons_test_username meritcommons_test_password);
use Mojo::Server::Prefork;
use MeritCommons;
use Mojolicious::Lite;
use Data::Dumper;
use Mojo::UserAgent;
require File::Temp;
use Mojo::JSON qw/encode_json decode_json/;
use File::Temp ();
use File::Temp qw/ tempfile tempdir :seekable /;

my $app = new MeritCommons;
$app->config('cookie_domain', '127.0.0.1');
$app->config('cookie_top_domain', '127.0.0.1');

# Emulated SP route
$app->routes->get('/sp/proxy_service/:num')->to(cb => sub {
    my ($self) = @_;

    my $ticket = $self->param('ticket');
    my $num = $self->param('num');

    if ($ticket) {
        # User is trying to log in
        my $ua = Mojo::UserAgent->new;

        my $service_validate_response = $ua->get("https://127.0.0.1:8443/cas/serviceValidate" => form => {
            ticket => $ticket,
            service => "https://127.0.0.1:8443/sp/proxy_service/" . $num,
            pgtUrl => "https://127.0.0.1:8443/sp/backend/" . $num
        })->res->body;

        my $dom = Mojo::DOM->new($service_validate_response);

        my $user = $dom->find('user')->[0];

        if ($user) {
            $self->render(text => $user->text);                
        } else {
            $self->render(text => "Authentication failure", status => 403);
        }
    } else {
        $self->redirect_to("https://127.0.0.1:8443/cas/login");
    }
});

# Emulated backend service route
$app->routes->get('/sp/backend/:num')->to(cb => sub {
    my ($self) = @_;

    my $pgt_iou = $self->param('pgtIou');
    my $pgt_id = $self->param('pgtId');
    my $num = $self->param('num');

    # Get a proxy ticket using the proxy granting ticket
    my $ua = Mojo::UserAgent->new;
    my $proxy_response = $ua->get("https://127.0.0.1:8443/cas/proxy" => form => {
        pgt => $pgt_id,
        targetService => "https://127.0.0.1:8443/sp/target_service"
    });

    # Stash the result variables
    my $dom = Mojo::DOM->new($proxy_response->res->body);
    my $pt_id = $dom->find('proxyticket')->[0]->text;
    test_stash({proxy_response => $proxy_response->res->body, pt_id => $pt_id, pgt_id => $pgt_id});

    $self->render(text => "ok");
});

my $prefork = Mojo::Server::Prefork->new(app => $app, workers => 5, listen => ['https://*:8443']);

# Delete the temp stash if it exists
if (-e "/tmp/test_stash") { 
    unlink("/tmp/test_stash"); 
}

# Simple file-based storage for passing test data between forked processes
sub test_stash {
    my ($data) = @_;
    my $filename = "/tmp/test_stash";

    if ($data) {
        # Write
        my $fh;
        open($fh, '>', $filename) or die "Couldn't open: $!";
        print $fh encode_json($data);
        close $fh;        
    } else {
        # Fetch
        open(INFO, $filename);  
        my @lines = <INFO>;    
        close(INFO);    
        my $string = "";

        foreach (@lines){
            $string .= $_;
        }

        return decode_json($string);
    }
}

if (my $pid = fork()) {    
    sleep(1); # Wait a second for the server thread to start up

    my $t = Test::Mojo->new($app);

    # Start the testing    
    $t->ua->max_redirects(5);    

    # Request the service provider URL, we should get bounced to the log in screen
    $t->get_ok("https://127.0.0.1:8443/sp/proxy_service/1")
        ->status_is(200)
        ->content_like(qr/Log In/i);

    my $lt = $t->tx->res->dom()->find('input[name="lt"]')->[0]->attr('value');

    if ($meritcommons_test_username && $meritcommons_test_username) {
        # Ensure that the user can log into the service provider.  The service provider should
        # also allow a backend service to get a proxy granting ticket, and that backend service
        # should request a proxy ticket
        $t->post_ok(("https://127.0.0.1:8443/cas/login") => form => {
            username => $meritcommons_test_username,
            password => $meritcommons_test_password,
            renew => 0,
            service => "https://127.0.0.1:8443/sp/proxy_service/1",
            warn => "",
            lt => $lt
        })->status_is(200)->content_is($meritcommons_test_username);

        # Validate that a proxy ticket was created
        my $response = test_stash()->{proxy_response};
        ok($response =~ qr/proxySuccess/i);

        # Validate the proxy ticket, and get another proxy granting ticket and proxy ticket
        my $pt_id = test_stash()->{pt_id};

        $t->get_ok("https://127.0.0.1:8443/cas/proxyValidate" => form => {
            ticket => $pt_id,
            service => "https://127.0.0.1:8443/sp/target_service",
            pgtUrl => "https://127.0.0.1:8443/sp/backend/2"
            })->status_is(200);
        
        $pt_id = test_stash()->{pt_id};

        # Validate the new proxy ticket, and verify that two proxies are listed in the output
        $t->get_ok("https://127.0.0.1:8443/cas/proxyValidate" => form => {
            ticket => $pt_id,
            service => "https://127.0.0.1:8443/sp/target_service"
            })->status_is(200)->content_like(qr/backend\/1/i)->content_like(qr/backend\/2/i);

        # PGT tickets can be used again
        my $pgt_id = test_stash()->{pgt_id}; 
        my $proxy_response = $t->get_ok("https://127.0.0.1:8443/cas/proxy" => form => {
            pgt => $pgt_id,
            targetService => "https://127.0.0.1:8443/sp/target_service"
        })->content_like(qr/proxySuccess/i);

        # Ensure logouts work
        $t->get_ok("https://127.0.0.1:8443/cas/logout")
            ->status_is(200)->content_like(qr/You have been logged out/i);

        # PGT should no longer be valid after logout
        $pgt_id = test_stash()->{pgt_id}; 
        $proxy_response = $t->get_ok("https://127.0.0.1:8443/cas/proxy" => form => {
            pgt => $pgt_id,
            targetService => "https://127.0.0.1:8443/sp/target_service"
        })->content_like(qr/BAD_PGT/i);            
    } else {
        warn "Cannot test CAS without meritcommons_test_username and meritcommons_test_password";
    }

    done_testing();

    # Kill the server
    kill 'HUP', $pid;
} else {
    $prefork->run;
}
