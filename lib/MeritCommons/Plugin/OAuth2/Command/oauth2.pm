#    MeritCommons Portal
#    Copyright 2016 Wayne State University
#    All Rights Reserved

package MeritCommons::Plugin::OAuth2::Command::oauth2;

use Mojo::Base 'Mojolicious::Command';
use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Crypt::Digest qw/digest_data_hex/;
use Crypt::X509;
use Crypt::PK::RSA;
use Mojo::UserAgent;
use Mojo::DOM;
use Mojo::Util qw/b64_decode b64_encode/;

has description => "Management Interface for the OAuth2 plugin\n";
has subcommands => sub {
    [
        [qw/client/],
    ];
};

sub run {
    my ($self, @args) = @_;

    # extract sub command
    my ($sc) = shift @args;

    if ($sc) {
        if ($self->can("c_$sc")) {
            my $method = "c_$sc";
            return $self->$method(@args);
        }
        print "[error] unknown command '$sc'\n";
    } else {
        print $self->usage;
    }
}

sub c_scope {
    my ($self, @args) = @_;

    unless ($args[0]) {
        print $self->usage('scope');
        exit;
    }

    my $scope_options = {};

    GetOptionsFromArray(
        \@args,
        'c|common-name=s' => \$scope_options->{common_name},
        'u|unique-id=s' => \$scope_options->{unique_id},
        'd|description=s' => \$scope_options->{description},
        'o|owner=s' => \my $owner,
    );

    my $actor;
    if ($owner) {
        $actor = $self->app->user($owner);
    } else {
        $actor = $self->app->user(1);
    }

    if ($args[0] eq "list") {
        print "OAuth2 Scopes\n\n";
        printf("%-25s %-37s %-25s %-50s\n", "Common Name", "Unique ID", "Modify Time", "Description");
        print "-" x 25 . " " . "-" x 37 . " " . "-" x 25 . " " . "-" x 50 . "\n";
        foreach my $scope ($self->app->m->resultset('MeritCommons::Plugin::OAuth2::Model::Scope')->all) {
            printf("%-25s %-37s %-25s %-50s\n",
                substr($scope->common_name, 0, 25),
                $scope->unique_id,
                scalar(localtime($scope->modify_time)),
                substr($scope->description, 0, 75),
            );
        }
        print "\n";
    } elsif ($args[0] eq "info") {
        my $scope = $self->app->oauth2->scope($scope_options->{unique_id} // $scope_options->{common_name});
        if ($scope) {
            print "Scope Information for '@{[$scope->common_name]}':\n\n";
            print "Unique ID    : @{[$scope->unique_id]}\n";
            print "Modify Time  : @{[scalar localtime $scope->modify_time]}\n";
            print "Description  : @{[$scope->description]}\n";
            print "\n";
        } else {
            say "Scope not found (try --common-name or --unique_id)";
        }
    } elsif ($args[0] eq "delete") {
        my $scope = $self->app->oauth2->remove_scope($scope_options->{unique_id} // $scope_options->{common_name}, $actor);
        if ($scope->{success}) {
            say "Deleted scope '@{[$scope->{common_name}]}' (@{[$scope->{unique_id}]})";
        } else {
            say "Error: " . $scope->{error};
        }
    } elsif ($args[0] eq "add") {
        my $scope = $self->app->oauth2->create_scope($scope_options, $actor);

        if ($scope->{success}) {
            print "\nSuccessfully created scope\n";
            print "-----------------------------------------------------------\n";           
            print "Common Name    : @{[$scope->{common_name}]}\n";
            print "Unique ID      : @{[$scope->{unique_id}]}\n";
            print "Description    : @{[$scope->{description}]}\n";
            print "\n";
        } else {
            say "Error: " . $scope->{error};
        }
    }
}

sub c_client {
    my ($self, @args) = @_;

    unless ($args[0]) {
        print $self->usage('client');
        exit;
    }

    my $client_options = {};

    GetOptionsFromArray(
        \@args,
        'c|common-name=s' => \$client_options->{common_name},
        'u|unique-id=s' => \$client_options->{unique_id},
        's|certificate=s' => \$client_options->{certificate},
        'y|use-system-cert' => \$client_options->{meritcommons_certificate},
        'd|description=s' => \$client_options->{description},
        'b|callback-url=s' => \$client_options->{callback_url},
        'o|owner=s' => \my $owner,
    );

    my $actor;
    if ($owner) {
        $actor = $self->app->user($owner);
    } else {
        $actor = $self->app->user(1);
    }

    if ($args[0] eq "list") {
        print "Configured OAuth2 Clients\n\n";

        printf("%-24s %-16s %-37s %-25s\n", "Common Name", "Thumbprint", "Unique ID", "Modify Time");
        print "-" x 24 . " " . "-" x 16 . " " . "-" x 36 . " " . "-" x 25 . "\n";
        foreach my $client ($self->app->m->resultset('MeritCommons::Plugin::OAuth2::Model::Client')->all) {
            printf("%-24s %-16s %-37s %-25s\n", 
                substr($client->common_name, 0, 24), 
                substr($client->thumbprint, 0, 7) . ".." . substr($client->thumbprint, length($client->thumbprint) - 7, 7), 
                $client->unique_id,
                scalar(localtime($client->modify_time)),
            );
        }

        print "\n";
    } elsif ($args[0] eq "info") {
        my $client = $self->app->oauth2->client($client_options->{unique_id} // $client_options->{common_name});
        if ($client) {
            print "Client information for '@{[$client->common_name]}'\n\n";
            print "Unique ID      : @{[$client->unique_id]}\n";
            print "Callback URL   : @{[$client->callback_url]}\n";
            print "Owner          : @{[$client->meritcommons_user->common_name]} (@{[$client->meritcommons_user->userid]})\n";
            print "Thumbprint     : @{[$client->thumbprint]}\n" if $client->thumbprint;
            print "Description    : @{[$client->description]}\n" if $client->description;
            print "Create Time    : @{[scalar localtime $client->create_time]}\n";
            print "Modify Time    : @{[scalar localtime $client->modify_time]}\n";
            print "#Tokens Issued : @{[$client->tokens->count]}\n";
            print "\n";
            print "Certificate    : @{[$client->certificate]}\n" if $client->certificate;
            print "\n";
        } else {
            print "Client not found (try --common-name, --unique-id, or --thumbprint)\n";
        }
    } elsif ($args[0] eq "delete") {
        my $client = $self->app->oauth2->remove_client($client_options->{unique_id} // $client_options->{common_name}, $actor);
        if ($client->{success}) {
            print "Deleted client '@{[$client->{common_name}]}' (@{[$client->{unique_id}]})\n";
        } else {
            say "Error: " . $client->{error};
        }
    } elsif ($args[0] eq "add") {
        my $client = $self->app->oauth2->create_client($client_options, $actor);

        if ($client->{success}) {
            print "\nSuccessfully created client\n";
            print "-----------------------------------------------------------\n";           
            print "Client ID      : @{[$client->{unique_id}]}\n";
            print "Callback URL   : @{[$client->{callback_url}]}\n";
            print "\n";
            print <<"EOF";
This is your secret.  It has been generated and printed for you here.  It is
IRRETRIEVABLE by the MeritCommons system admins.  Store somewhere safe, and do 
not lose this secret.

########################################
#  YOUR SUPER IMPORTANT CLIENT SECRET  #
#                                      #
#   $client->{client_secret}   #
#                                      #
########################################

EOF
        } else {
            say "Error: " . $client->{error};
        }
    }
}

sub usage {
    my ($self, @args) = @_;

    my $subcommand;
    unless ($subcommand = $args[0]) {
        $subcommand = $ARGV[1];
    }

    # empty string avoids 'undefined' errors
    $subcommand = '' unless $subcommand;

    if ($subcommand eq "client") {
        return <<"EOF";
Usage: meritcommons oauth2 client [OPERATION] [OPTIONS]

These operations are available for 'oauth2 client':
        add                 Configure a new client
        list                List existing OAuth2 client configurations
        delete              Remove an existing OAuth2 client
        info                Print information about an existing client configuration

These options are available for 'oauth2 client':
    -c, --common-name       The common name of the client (url preferred)
    -u, --unique-id         The unique id of the client (query only)
    -s, --certificate       The RSA certificate this client will use for signatures (will
                            be ignored if -y is used)
    -y, --use-system-cert   Overrides -s, MeritCommons will sign all assertions requested by
                            this client.  The client itself will never create its own 
                            assertions
    -d, --description       Client description
    -b, --callback-url      The default URL we should direct clients to once they obtain an 
                            authorization token.
                            defaults to '@{[$self->app->config->{front_door_url}]}/oauth2/callback'

EOF
    } elsif ($subcommand eq "scope") {
        return <<"EOF";
Usage: meritcommons oauth2 scope [OPERATION] [OPTIONS]

These operations are available for 'oauth2 scope':
        add                 Add a new scope
        list                List existing OAuth2 scopes
        delete              Remove an existing OAuth2 scope
        info                Print information about an existing scope

These options are available for 'oauth2 scope':
    -c, --common-name       The common name of the scope
    -u, --unique-id         The unique id of the scope (query only)
    -d, --description       Scope description

EOF
    } else {
        return <<"EOF";
Usage: meritcommons oauth2 [COMMAND] [OPTIONS]

The following commands are available for 'oauth2':
        client              Add and manage configured OAuth2 clients
        scope               Add and manage configured OAuth2 scopes

EOF
    }
}

1;