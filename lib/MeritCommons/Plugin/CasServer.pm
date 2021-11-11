#    MeritCommons Portal
#    Copyright 2013 Wayne State University
#    All Rights Reserved

package MeritCommons::Plugin::CasServer;
use Mojo::Base 'MeritCommons::Plugin';
use warnings;

our $VERSION = 0.02;
our $SCHEMA_VERSION = 4;

# MeritCommons::Plugins use _register instead of register.
sub _register {
    my ($self, $app) = @_;

    # Register plugins
    $app->plugin('CasServerUtil');

    # register routes
    $app->routes->get('/cas/login')->to('Plugin::CasServer::Controller::CasServer#login');
    $app->routes->post('/cas/login')->to('Plugin::CasServer::Controller::CasServer#login_submit');
    $app->routes->get('/cas/logout')->to('Plugin::CasServer::Controller::CasServer#logout');
    $app->routes->get('/cas/cancel_authentication')
      ->to('Plugin::CasServer::Controller::CasServer#cancel_authentication');
    $app->routes->get('/cas/validate')->to('Plugin::CasServer::Controller::CasServer#validate');
    $app->routes->post('/cas/samlValidate')->to('Plugin::CasServer::Controller::CasServer#saml_validate');
    $app->routes->get('/cas/serviceValidate')->to('Plugin::CasServer::Controller::CasServer#service_validate');
    $app->routes->get('/cas/proxyValidate')->to('Plugin::CasServer::Controller::CasServer#proxy_validate');
    $app->routes->get('/cas/p3/serviceValidate')->to('Plugin::CasServer::Controller::CasServer#service_validate');
    $app->routes->get('/cas/p3/proxyValidate')->to('Plugin::CasServer::Controller::CasServer#proxy_validate');
    $app->routes->get('/cas/proxy')->to('Plugin::CasServer::Controller::CasServer#proxy');
    $app->routes->get('/cas/test')->to('Plugin::CasServer::Controller::CasServer#test');

    $app->helper('casserver.plugin' => sub { return $self } );
    my $config = $self->plugin_config;
    $app->helper('casserver.plugin_config' => sub { return $config } );

    # this is used to determine if we need to redirect to the auth_url
    $app->on(unauthenticated_access => sub {
        my ($app, $c) = @_;

        if ($c->req->url->path =~ /^\/cas\/(?:validate|samlValidate|serviceValidate|proxyValidate|proxy)/o) {
            $c->stash(redirect_to_auth_url => 0);
        } else {
            # if something else already said don't redirect, then we don't redirect
            unless (defined $c->stash('redirect_to_auth_url') && $c->stash('redirect_to_auth_url') == 0) {
                $c->stash(redirect_to_auth_url => 1);
            }
        }
    });

    $app->on(
        session_info => sub {
            my ($self, $c) = @_;
            my $si = $c->stash('session_info') || {};

            if ($c->meritcommons_session) {
                my $time_left = $c->meritcommons_session->cas_session_expire->first - time;

                if ($time_left) {
                    $si->{meritcommons_session}->{cas_capable} = 1;
                    $si->{meritcommons_session}->{cas_capable_for} = $time_left;
                }
            }
            
            $c->stash(session_info => $si);
        }
    );

    $app->on(
        session_established => sub {
            my ($self, $c, $session) = @_;

            my $timeout = 0;
            if (my $user = $c->active_user) {
                my $roles = { other => 1 };
                foreach my $role ($user->roles) {
                    $roles->{ $role->common_name } = 1;
                }

                foreach my $role (@{ $c->casserver->plugin_config->{cas_role_order} }) {
                    if (exists($roles->{$role})) {
                        $timeout = $c->casserver->plugin_config->{cas_inactivity_timeout}->{$role};
                        last;
                    }
                }
            }

            $session->cas_session_expire(time + $timeout);
        }
    );

    $app->on(
        session_refreshed => sub {
            my ($self, $c, $session) = @_;
            my $timeout = 0;
            if (my $user = $session->meritcommons_user) {
                my $roles = { other => 1 };
                foreach my $role ($user->roles) {
                    $roles->{ $role->common_name } = 1;
                }

                foreach my $role (@{ $c->casserver->plugin_config->{cas_role_order} }) {
                    if (exists($roles->{$role})) {
                        $timeout = $c->casserver->plugin_config->{cas_inactivity_timeout}->{$role};
                        last;
                    }
                }
            }

            # only update if the external session expire has not yet elapsed.
            if ($session->cas_session_expire && ($session->cas_session_expire->first > time)) {
                $session->cas_session_expire(time + $timeout);
            }
        }
    );

    $app->on(
        session_destroyed => sub {
            my ($self, $c, $session) = @_;

            my $tickets_deleted;
            if (my $rs = $c->m->resultset('MeritCommons::Plugin::CasServer::Model::Ticket')->search({meritcommons_session => $session->id})) {
                $tickets_deleted = $rs->delete;
            }

            if ($tickets_deleted > 0) {
                $c->audit_log("CasServer - @{[$session->meritcommons_user->userid]} session_destroyed; removed $tickets_deleted tickets associated with " . 
                    "session_id @{[$session->session_id]}");
            }
        }
    );

    return $self;
}

return 1;
