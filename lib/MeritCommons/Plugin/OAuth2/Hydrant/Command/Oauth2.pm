#   MeritCommons Portal
#   Copyright 2016 Wayne State University
#   All Rights Reserved

package MeritCommons::Plugin::OAuth2::Hydrant::Command::Oauth2;

use Mojo::Base qw(MeritCommons::Hydrant::Command);
use Mojo::Util qw/decode encode/;
use Mojo::JSON qw/to_json/;

has subcommands => 1;
has expects => 'json';

sub command {
    my ($self, $data, $command) = @_;

    if ($command) {
        $command = "_" . $command;
        if ($self->can($command)) {
            $self->send($self->$command($data));            
        } else {
            $self->send("Invalid command.");
        }
    } else {
        $self->send("No command specified.");
    }
}

sub _create_client {
    my ($self, $data) = @_;

    return $self->controller->oauth2->create_client($data, $self->controller->active_user);
}

sub _remove_client {
    my ($self, $data) = @_;

    return $self->controller->oauth2->remove_client($data->{unique_id}, $self->controller->active_user);
}

sub _modify_client {
    my ($self, $data) = @_;

    return $self->controller->oauth2->modify_client($data, $self->controller->active_user);
}

sub _get_client {
    my ($self, $data) = @_;

    my $c = $self->controller;

    my $actor = $c->active_user;
    if ($actor->has_role("developer") || $actor->is_admin) {
        if (my $client = $c->app->oauth2->client($data->{unique_id})) {
            if ($client->meritcommons_user == $actor->id || $actor->is_admin) {
                return {
                    unique_id => $client->unique_id,
                    common_name => $client->common_name,
                    description => $client->description,
                    thumbprint => $client->thumbprint,
                    callback_url => $client->callback_url,
                    success => 1,
                };
            } else {
                return { 
                    error => "You do not have permission to do this.",
                    success => 0,
                };
            }
        } else {
            return { 
                error => "The client specified (" . $data->unique_id . ") could not be found.",
                success => 0, 
            };
        }
    } else {
        return { 
            error => "You do not have permission to do this.",
            success => 0,
        };
    }
}

sub _create_scope {
    my ($self, $data) = @_;

    return $self->controller->oauth2->create_scope($data, $self->controller->active_user);
}

sub _remove_scope {
    my ($self, $data) = @_;

    return $self->controller->oauth2->remove_scope($data->{unique_id}, $self->controller->active_user);
}

sub _modify_scope {
    my ($self, $data) = @_;

    return $self->controller->oauth2->modify_scope($data, $self->controller->active_user);
}

sub validate {
    my ($self, $arg, $command) = @_;

    if (my $v = $self->validation) {
        $v = $v->input($arg);
        if ($command eq "create_client") {
            $v->required('common_name')->like($self->F_PHRASE);
            $v->required('meritcommons_certificate')->in(qw/0 1/);
            $v->optional('certificate');
            $v->required('description');
            $v->optional('callback_url')->like($self->F_URI);
        } elsif ($command eq "remove_client") {
            $v->required('unique_id')->like($self->F_UUID);
        } elsif ($command eq "get_client") {
            $v->required('unique_id')->like($self->F_UUID);
        } elsif ($command eq "modify_client") {
            $v->required('unique_id')->like($self->F_UUID);
            $v->required('common_name')->like($self->F_PHRASE);
            $v->required('description');
            $v->optional('callback_url')->like($self->F_URI);
        } elsif ($command eq "create_scope") {
            $v->required('common_name')->like($self->F_PHRASE);
            $v->required('description');
        } elsif ($command eq "remove_scope") {
            $v->required('unique_id')->like($self->F_UUID);
        } elsif ($command eq "modify_scope") {
            $v->required('unique_id')->like($self->F_UUID);
            $v->required('common_name')->like($self->F_PHRASE);
            $v->required('description');
        }
        
        return $v;
    }

    return undef;
}

1;