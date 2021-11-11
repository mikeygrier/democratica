package MeritCommons::Plugin::OAuth2::Controller::Web;

use Mojo::Base 'Mojolicious::Controller';
use Time::Piece;

sub list {
    my ($c) = @_;

    if ($c->active_user && ($c->active_user->has_role("developer") || $c->active_user->is_admin)) {
        my (@clients, @scopes);
        if ($c->active_user->is_admin) {
            @clients = $c->app->m->resultset('MeritCommons::Plugin::OAuth2::Model::Client')->all;
            @scopes = $c->app->m->resultset('MeritCommons::Plugin::OAuth2::Model::Scope')->all;
        } else {
            @clients = $c->app->m->resultset('MeritCommons::Plugin::OAuth2::Model::Client')->search({ meritcommons_user => $c->active_user->id })->all;
            #@scopes = $c->app->m->resultset('MeritCommons::Plugin::OAuth2::Model::Scope')->search({ meritcommons_user => $c->active_user->id })->all;
        }

        $c->stash(clients => \@clients);
        $c->stash(scopes => \@scopes);
        $c->render(template => 'web/list');
    } else {
        $c->reply->not_found;
    }
}

1;