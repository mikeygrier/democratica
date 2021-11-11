package WWW::Romeo;

our $VERSION = '0.21.02';

# release type (alpha, beta, pre-release, release, stable) a/b/pr/r/s
my $RELEASE = 'a';

use DBI;
use Carp;
use Cache::Memory;
use Time::HiRes;
use Exporter;
use Class::Accessor;
use Apache2::Request;
use Apache2::Connection;
use Apache2::Cookie;
use Apache2::RequestRec;
use Apache2::Const qw /:common/;
use Template;

# WWW::Romeo sessions
use WWW::Romeo::Session;

# Ported BadNews::Config / LDIP Config (Going YAML)
use WWW::Romeo::Config;

# Schema Facilities
use WWW::Romeo::DB;

# We can export c & tc for Romeo::Extensions
our @ISA = qw/Class::Accessor Exporter/;
our @EXPORT_OK = qw/c tc/;

# Make some accessors
__PACKAGE__->mk_accessors(qw/
    start_time      theme           instance    romeo_location
    user_agent      agent_is_robot  cgi         template        uri
    uri_components  r
    /);

#
# global, the current Apache request
#

our $current_request;

# I donno why i'm still supporting CGI in 2008
my ($cc, $tc, $ec); 
if ($ENV{MOD_PERL}) {
    # season to taste
    $cc = Cache::Memory->new(namespace => 'romeo-config', default_expires   => '3600 sec');
    $tc = Cache::Memory->new(namespace => 'romeo-templates', default_expires => '300 sec');
    $ec = Cache::Memory->new(namespace => 'romeo-extensions', default_expires => '600 sec');
}

sub new {
    my ($class, %attribs) = @_;
    my $self = bless (\%attribs, $class);
    $self->setup();
    return $self;
}


sub db {
    my ($self) = @_;
    unless ($self->{dbic}) {
        if ($self->c->DB_USER) {
            $self->{dbic} = WWW::Romeo::DB->connect($self->c->DSN, $self->c->DB_USER, $self->c->DB_PASS);
        } else {
            $self->{dbic} = WWW::Romeo::DB->connect($self->c->DSN);
        }
    }
    return $self->{dbic};
}

sub deploy {
    my ($self) = @_;
    $self->db->deploy(
        {
            add_drop_table  =>  1,
        }
    );
}

sub user {
    my ($self, $username) = @_;
    return $self->db->resultset('User')->search(
        {
            username        =>          $username,
        }
    )->first;
}

sub user_by_email {
    my ($self, $email) = @_;
    return $self->db->resultset('User')->search(
        {
            email           =>          $email,
        }
    )->first;
}

*open_db = \&db;

sub setup {
    my ($self) = @_;
    return;
}

sub c {
    my ($config, $config_file);

    if ($current_request) {
        unless ($config_file = $current_request->dir_config('RomeoConfigFile')) {
            $config_file = "$ENV{DOCUMENT_ROOT}/../conf/romeo.yml";
        }
    } else {
        # command line scripts, etc.. no apache config information
        # set document root export DOCUMENT_ROOT=/path/to/some/dir/ to get around this
        $config_file = "$ENV{DOCUMENT_ROOT}/../conf/romeo.yml";
    }

    # look in a global place if there isn't a more specific one.
    unless (-e $config_file) {
        $config_file = '/etc/praux/praux.conf';
    }

    if ($ENV{MOD_PERL}) {
        my $cached_conf = $cc->get($config_file);
        if ($cached_conf) {
            $config = $cached_conf;
        } else {
            $config = WWW::Romeo::Config->new(ConfigFile =>  $config_file) unless $config;
            $cc->set($config_file, $config);
        }
    } else {
        # we're not running under mod perl.. so create the config object and return
        $config = WWW::Romeo::Config->new(ConfigFile =>  $config_file);
    }
    return $config;
}

# bN FrontEnd Code Follows

# implementation summary
# sessions, themes, configuration
sub handler {
    my ($r) = shift;

    # set this right away
    $current_request = $r;

    # get all the data we need to handle this request.
    my $start_time = Time::HiRes::time();
    my $apr = Apache2::Request->new($r);
    my $cookies = Apache2::Cookie->fetch($r);
    my $location = $r->location;
    my $romeo_location = $location =~ /^\/+$/o ? undef : $location;
    my $uri = $r->uri;
    my ($http_version) = $r->protocol =~ /(\d+\.\d+)/o;
    my $user_agent = $r->headers_in->get('User-Agent');

    # now data from parameters
    my $page = $apr->param('page');
    my $theme = $apr->param('theme');
    my $sticky_theme = $apr->param('sticky_theme');
    my %parms = $r->args;

    # regex to check for robots
    my ($agent_is_robot) = $user_agent =~ /(?:check_http|avsearch|gulliver|mercator|bigbrother|inktomi|scooter|appie|newscan-online|libwww-perl|searchtone|asterias|indexer|ync|slurp|seek|crawl|spider|bot|smallbear|lwp|echo|flash|load|link|keynote|agent|map|attache|webtool|sweep|wget|extract|fetch|T-H-U-N-D-E-R-S-T-O-N-E|robot|proxy|libwww|whatsup_gold|cnnit|yandex|ask|spinn3r|linguee)/io;

    # we use these environment variables to track which instance we are, so we need them.
    $ENV{SERVER_NAME} = $r->hostname;
    $ENV{DOCUMENT_ROOT} = $r->document_root;

    # retrieve / establish sessions
    my ($anon_session, $user_session, $cookie);
    if ($cookies->{romeo_anon}) {
        $anon_session = WWW::Romeo::Session->new(session_id        =>      $cookies->{romeo_anon}->value);
        if ($anon_session) {
            $anon_session->from_cookie(1);
            $anon_session->ip_address($r->connection->remote_ip);
            $anon_session->page_count($anon_session->page_count + 1);
        } else {
            $anon_session = WWW::Romeo::Session->new(Anon  =>  1);
            $cookie = Apache2::Cookie->new($r,  -name       =>      'romeo_anon',
                                                -value      =>      $anon_session->session_id,
                                                -path       =>      '/',
                                                -domain     =>      $anon_session->c->COOKIE_DOMAIN
                                            );
            # add the cookie to the request.
            $cookie->bake($r);
        }
    } else {
        $anon_session = WWW::Romeo::Session->new(Anon  =>  1);
        $cookie = Apache2::Cookie->new($r,  -name       =>      'romeo_anon',
                                            -value      =>      $anon_session->session_id,
                                            -path       =>      '/',
                                            -domain     =>      $anon_session->c->COOKIE_DOMAIN
                                        );
        # add the cookie to the request.
        $cookie->bake($r);
    }

    if ($cookies->{romeo_auth}) {
        $user_session = WWW::Romeo::Session->new(session_id    =>  $cookies->{romeo_auth}->value);
        if ($user_session) {
            $user_session->ip_address($r->connection->remote_ip);
            $user_session->page_count($user_session->page_count + 1);
            $user_session->from_cookie(1);
        }
    }

    # init a few things, we need the uri stuff to pull theme infos
    my ($path) = $uri =~ /^$location\/*(.*)$/o;
    my @romeo_uri = split(/\//o, $path);

    if ($romeo_uri[0] eq "theme") {
        $theme = $romeo_uri[1];
        $romeo_location = $romeo_location . "/$romeo_uri[0]/$romeo_uri[1]/";
        @romeo_uri = @romeo_uri[2..$#romeo_uri];
    }

    # get the theme out of here
    my $use_theme;
    if ($theme) {
        if ($sticky_theme) {
            $user_session->theme($theme) if $user_session;
            $anon_session->theme($theme) if $anon_session;
        }
        $use_theme = $theme;
    } else {
        $use_theme = $anon_session->theme if $anon_session;
        $use_theme = $user_session->theme if $user_session;
    }

    $use_theme = __PACKAGE__->c->DEFAULT_THEME unless $use_theme;

    # initialize our template engine
    my $template = $tc->get($ENV{SERVER_NAME});
    unless ($template) {
        my $tcd = __PACKAGE__->c->TEMPLATE_COMPILE_DIR ? __PACKAGE__->c->TEMPLATE_COMPILE_DIR : "/tmp/";
        my $tag_style = __PACKAGE__->c->TEMPLATE_TAG_STYLE ? __PACKAGE__->c->TEMPLATE_TAG_STYLE : 'template';
        $template = Template->new(
            {
                INCLUDE_PATH            =>      __PACKAGE__->c->THEME_PATH,
                COMPILE_DIR             =>      $tcd . __PACKAGE__->c->COOKIE_DOMAIN,
                #DEBUG                  =>      'provider',
                #DEBUG_FORMAT           =>      '<!-- $file line $line : [% $text %] -->',
                TRIM                    =>      1,
                PRE_CHOMP               =>      1,
                POST_CHOMP              =>      1,
                TAG_STYLE               =>      $tag_style,
                RECURSION               =>      1,
                CONSTANTS               =>      {
                    prOH => '<img src="/img/oh_symbol_32.png" height="16" width="16" title="Praux prOH"/>',
                    prENT => '<img src="/img/ent_symbol_32.png" height="16" width="16" title="Praux prENT"/>',
                    prOH16 => '<img src="/img/oh_symbol_32.png" height="16" width="16" title="Praux prOH"/>',
                    prENT16 => '<img src="/img/ent_symbol_32.png" height="16" width="16" title="Praux prENT"/>',
                    prOH24 => '<img src="/img/oh_symbol_32.png" height="24" width="24" title="Praux prOH"/>',
                    prENT24 => '<img src="/img/ent_symbol_32.png" height="24" width="24" title="Praux prENT"/>',
                    prOH32 => '<img src="/img/oh_symbol_32.png" height="32" width="32" title="Praux prOH"/>',
                    prENT32 => '<img src="/img/ent_symbol_32.png" height="32" width="32" title="Praux prENT"/>',
                }
            }
        );
        $tc->set($ENV{SERVER_NAME}, $template);
    }

    # create our object :D
    my $self = __PACKAGE__->new(
        start_time          =>          $start_time,
        anon_session        =>          $anon_session,
        user_session        =>          $user_session,
        cgi                 =>          $apr,
        apr                 =>          $apr,
        instance            =>          $r->hostname,
        theme               =>          $use_theme,
        romeo_location      =>          $romeo_location,
        agent_is_robot      =>          $agent_is_robot,
        user_agent          =>          $user_agent,
        uri                 =>          $uri,
        uri_components      =>          \@romeo_uri,
        query_string        =>          $r->args,
        template            =>          $template,
        parsed_query_string =>          \%parms,
        r                   =>          $r,
    );

    #warn "$$ Context lifecycle: $self created to serve $uri.\n";

    if ($self->c->DEFAULT_EXTENSION) {
        if ($self->c->EXTENSION_OVERRIDE) {
            # always run the default extension
            return $self->run_extension($self->c->DEFAULT_EXTENSION, @romeo_uri);
        } else {
            # load & run extension
            return $self->run_extension(@romeo_uri);
        }
    } else {
        if ($path) {
            # LEGACY SUPPORT. FU.
            if ($romeo_uri[0] eq "page") {
                shift(@romeo_uri);
                $r->content_type('text/html');
                $self->render_page($romeo_uri[0]);
                return OK;
            } else {
                return $self->run_extension(@romeo_uri);
            }
        } else {
            # display index.htmlt
            $r->content_type('text/html');
            $self->render_page('index');
            return OK;
        }
    }
}

sub app_base {
    my ($self) = @_;
    my $server = $self->r->get_server_name;
    my $port = $self->r->get_server_port;

    my $base;
    if ($port == 80) {
        $base = "http://$server";
    } elsif ($port == 443) {
        $base = "https://$server";
    } else {
        $base = "http://$server:$port";
    }
    return $base . $self->romeo_location;
}

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    $romeo->r->content_type('text/html');
    $romeo->template->process($self->theme . "/error.tt2",
        {   
            error   =>      "'WWW::Romeo' can't be used as an extension."
        }
    );
}

# per-theme configuration file
sub tc {
    my ($self) = @_;
    my @paths = split(/:/, $self->c->THEME_PATH);
    my $config_file;
    foreach my $path (@paths) {
        $config_file = $path . "/" . $self->theme . "/conf/" . $self->theme . ".yml";
        if (-e $config_file) {
            last;
        } else {
            warn "Attempt to use theme config on " . $self->theme . ": $config_file not found.\n";
            return undef;
        }
    }

    if ($ENV{MOD_PERL}) {
        my $cached_conf = $cc->get($ENV{SERVER_NAME} . "_theme_config_" . $self->theme);
        if ($cached_conf) {
            $self->{theme_config} = $cached_conf;
        } else {
            $self->{theme_config} = WWW::Romeo::Config->new(ConfigFile  =>  $config_file);
            $cc->set($ENV{SERVER_NAME} . "_theme_config_" . $self->theme, $self->{theme_config});
        }
    } else {
        # we're not running under mod perl.. so create the config and return
        $self->{theme_config} = WWW::Romeo::Config->new(ConfigFile  =>  $config_file);
    }
    return $self->{theme_config};
}

# utility methods
sub render_page {
    my ($self, $page, $ns) = @_;
    my $t_ext = $self->c->TEMPLATE_FILE_EXT ? $self->c->TEMPLATE_FILE_EXT : 'htmlt';
    $page .= '.' . $t_ext unless $page =~ /^.+\.$t_ext$/o;
    $ns->{romeo} = $self;
    $ns->{fe} = $self;
    $self->template->process($self->theme . "/" . $page, $ns) or 
        $self->template->process($self->theme . "/error.$t_ext", 
        { 
            %$ns,
            error   => "Couldn't process " . $self->theme . "/$page: $!, $@", 
        }
    );
}

sub rendered_page {
    my ($self, $page, $ns) = @_;
    my $output;
    my $t_ext = $self->c->TEMPLATE_FILE_EXT ? $self->c->TEMPLATE_FILE_EXT : 'htmlt';
    $page .= '.' . $t_ext unless $page =~ /^.+\.$t_ext$/o;
    $ns->{romeo} = $self;
    $ns->{fe} = $self;
    $self->template->process($self->theme . "/" . $page, $ns, \$output) or 
        $self->template->process($self->theme . "/error.$t_ext", 
        { 
            %$ns,
            error   => "Couldn't process " . $self->theme . "/$page: $!, $@", 
        }, $output
    );
    return $output;
}

sub render_error {
    my ($self, $error, $ns) = @_;
    my $t_ext = $self->c->TEMPLATE_FILE_EXT ? $self->c->TEMPLATE_FILE_EXT : 'htmlt';
    $ns->{romeo} = $self;
    $ns->{error} = $error;
    $self->template->process($self->theme . "/error.$t_ext", $ns);
}

# returns an authenticated user, if there is one.. otherwise returns the anon session.
sub session {
    my ($self) = @_;
    my $session;
    $session = $self->{anon_session} if $self->{anon_session};
    $session = $self->{user_session} if $self->{user_session};

    return $session;
}

sub time_taken {
    my ($self) = @_;
    return sprintf('%.5f', (Time::HiRes::time() - $self->start_time));
}

sub param {
    my ($self, $key, @value) = @_;

    if (scalar(@value)) {
        # this is an application-layer set
        $self->{_params}->{$key} = \@value;
    } else {
        # don't do anything to data we already have cached.
        unless ($self->{_params}->{$key}) {
            # this is us getting it out of the request
            @value = ($self->cgi->param($key));
            $self->{_params}->{$key} = \@value;
        }
    }

    return wantarray ? (@{$self->{_params}->{$key}}) : $self->{_params}->{$key}->[0];
}

# praux needed this
sub param_was_sent {
    my ($self, $key) = @_;
    my $table = $self->cgi->param;
    if (exists($table->{$key})) {
        return 1;
    } else {
        return undef;
    }
}

sub run_extension {
    my ($self, @romeo_uri) = @_;

    unless ($ec) {
        warn "No extension cache found in the WWW::Romeo namespace -- extension performance will suffer greatly.\n";
    }

    if (my $eobj = $ec->get("Praux" . $romeo_uri[0])) {
        # it's in the cache...
        $eobj->romeo($self);
        return $eobj->handle_request($self, @romeo_uri);
    } else {
        my $ebc = $self->c->EXTENSION_BASE_CLASS ? $self->c->EXTENSION_BASE_CLASS : 'WWW::Romeo::Extension';

        my $extension = ucfirst($romeo_uri[0]);
        my $romeo_namespace = 1;
        eval "use $ebc\:\:$extension;";
        if ($@) {
            eval "use $extension;";
            if ($@) {
                $self->r->content_type('text/html');
                $self->render_error("Don't know how to handle $extension ($romeo_uri[0])... <br/> More info: $@");
                return OK;
            }
            $romeo_namespace = 0;
        }

        # This is a possible security hole, as it allows people to load arbitrary perl modules, so I'll give users a "way out"
        if (!$romeo_namespace && $self->c->PARANOID) {
            $self->r->content_type('text/html');
            $self->render_error("Illegal load of extension outside of the WWW::Romeo namespace $extension with <paranoid> set to true!");
            return OK;
        }
        my $eobj;

        if ($romeo_namespace) { 
            eval "\$eobj = $ebc\:\:$extension->new(\$self);";
        } else {
            eval "\$eobj = $extension->new(\$self);";
        }

        if ($@) {
            $self->r->content_type('text/html');
            $self->render_error("Error creating extension object for extension... $@");
            return OK;
        }

        if (ref($eobj)) {
            unless ($eobj->isa("WWW::Romeo::Extension")) {
                $self->r->content_type('text/html');
                $self->render_error("Not an extension object...");
                return OK;
            }
        } else {
            $self->r->content_type('text/html');
            $self->render_error("Not an object at all ... :(");
            return OK;
        }

        # the cache checks to see that it is a true WWW::Romeo::Extension object.. so we won't duplicate that work here..
        $ec->set("Praux" . $romeo_uri[0], $eobj);

        return $eobj->handle_request($self, @romeo_uri);
    }

}

sub DESTROY {
    my ($self) = @_;
    #warn "$$ Context lifecycle: $self destroied.\n";
}

1;

__END__

=head1 NAME

WWW::Romeo - Where for art thou?

=head1 SYNOPSIS

 PerlModule WWW::Romeo
 <Location />
    SetHandler perl-script
    PerlHandler WWW::Romeo
 </Location>

=head1 DESCRIPTION

WWW::Romeo is a web framework distilled from the remains of the BadNews content management system.  The overall philosophy 
of WWW::Romeo is to be as simple as possible, providing only the features that are absolutely necessary to most projects 
while keeping developers free to innovate the web.

=head1 ACCESSOR METHODS

=over 2

=item

B<start_time> - get/set the time this request started processing, by default it will be populated by WWW::Romeo with a Time::HiRes::time() value.

=item

B<theme> - get/set the theme this object was instantiated with, themes can come from the URI [% romeo.romeo_location %]/themes/<theme_name>/, 
the Session (theme value saved because of sticky_themes), HTTP parameters, or from the configuration file (default_theme).  You can also set it here before 
calling render_page.

$romeo->param('favorite_countries', qw/Spain Portugal Greece/);

=item

B<instance> - returns the hostname of this virtual host, and is used internally to figure out which virtual host that WWW::Romeo is serving 
content for.

=item

B<romeo_location> - returns the <Location> that WWW::Romeo is configured to serve.

=item

B<user_agent> - returns the client's provided web browser / user agent information.

=item

B<agent_is_robot> - returns true if the user agent was determined to be a robot.

=item

B<cgi> - returns this request's instantiated Apache2::Request object

=item

B<template> - returns this request's instantiated Template object

=item

B<uri> - returns this request's full uri as a string

=item

B<uri_components> - returns an array of the uri path AFTER romeo_location split by directory delimiter "/"

=item

B<request> - returns this request's instantiated Apache2::RequestRec object

=item

B<app_base> - returns the beginning of the application, in URL form e.g. http://myapp.com:8080/my/romeo/app/

=back

=head1 METHODS THAT DO STUFF

=over 2

=item

B<param> - get/set url parameters from the Apache2::Request object.  Since Apache 2.x's APR::Table is populated and made read-only, WWW::Romeo allows
you to set parameters here for the lifecycle of the request.  

=item 

B<new> - generic constructor, blesses a hash of passed attirbutes, most of the ACCESSOR METHODS specified above are initially populated here by the handler() method.

=item

B<db> - returns an instantiated WWW::Romeo::DB (DBIx::Class::Schema) object.

=item

B<deploy> - deploy's WWW::Romeo's schema using the DBIx::Class::Schema deploy method.  CAUTION: passes add_drop_table, and will DESTROY any data currently in the tables.

=item

B<user> - when passed a username, returns a WWW::Romeo::DB::User object.

my $user = $romeo->user('mikeyg');

=item

B<user_by_email> - similar to B<user>, but takes an email address as a parameter instead.

=item

B<c> - returns this instance's instantiated WWW::Romeo::Config object.

=item

B<tc> - returns this instance's theme configuration (WWW::Romeo::Config) for the currently selected theme.

=item

B<render_page> - renders the page <page_name>.<template_file_ext> using the instantiated Template object, takes arguments page_name (with or without extension), 
and a hashref containing the template namespace.

$romeo->render_page('beach_pictures', { title => 'Me and Kriss at the beach!' });

=item

B<render_error> - renders error.<template_file_ext> using the instantiated Template object, takes arguments error_string, and a hashref containing the template namespace.

$romeo->render_error('Lol, nub!');

=item

B<session> - returns a session for the user, either the authenticated user_session, or an anon_session if no authenticated session is found.

=item 

B<time_taken> - returns a %.5f float representing the amount of time since the request started processing.

=item

B<run_extension> - when passed the Apache2::RequestRec object, and the uri_components array, run_extension loads and runs a WWW::Romeo::Extension (or other) 
class's B<handle_request> method, instantiating its class and passing it the Apache2::RequestRec object, and the url_components array.  Will search 
the configured extension_base_class namespace first for the extension, or WWW::Romeo::Extension's namespace by default.  If nothing is found there, it will 
attempt to load the extension literally.

=back

=head1 AUTHOR

Michael Gregorowicz, E<lt>mike@mg2.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Michael Gregorowicz

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
