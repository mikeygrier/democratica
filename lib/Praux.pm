package Praux;

use base qw/WWW::Romeo::Extension/;

use Text::Wrap qw/wrap/;
use WWW::Romeo;
use Apache2::Const qw /:common/;
use Apache2::Util qw /ht_time/;
use Apache2::Cookie;
use Apache2::Log;
use Apache2::RequestUtil;
use Cache::Memcached;
use LWP::UserAgent;
use Data::UUID;
use Mail::Sender;
use Digest::MD5 qw/md5_hex/;
use Lingua::Stem::Snowball;
use Sphinx::Search;
use WWW::Facebook::API;
use XML::Simple;

# to process the resume!
use YAML::Syck;

# for date prettyness.
use POSIX qw /strftime/;

use Praux::DB;
use Praux::Session;
use Praux::Report;

# version
our $VERSION = "3.11.64"; # for workgroups!

# uuid generator
our $ug = Data::UUID->new;

# cache
our $memd = Cache::Memcached->new(
    {
        servers => [ '198.50.223.83:11211' ],
    }
);

# sphinx access - default config
our $spx = new Sphinx::Search;
$spx->SetServer('db.mg2.org', 9312);
$spx->SetMatchMode(SPH_MATCH_ANY);

my %urlc_map = (
    register => 'Praux::Url::Register',
    captcha => 'Praux::Url::Captcha',
    page => 'Praux::Url::Page',
    login => 'Praux::Url::Login',
    logout => 'Praux::Url::Logout',
    create_resume => 'Praux::Url::CreateResume',
    move_resume => 'Praux::Url::MoveResume',
    edit_resume => 'Praux::Url::EditResume',
    usersetpref => 'Praux::Url::UserSetPref',
    
    # togglables
    toggleables => 'Praux::Url::Toggleables',
    
    # just a heads up these are both the same thing.. 
    update_password => 'Praux::Url::UpdatePassword',
    change_password => 'Praux::Url::UpdatePassword',
    
    # so are these
    links_of_great_import => 'Praux::Url::ResumeLinks',
    important_links => 'Praux::Url::ResumeLinks',
    
    # password reset!
    pwr => 'Praux::Url::PasswordReset',
    rpw => 'Praux::Url::PasswordReset',
    
    # this is for the prauxtron
    json => 'Praux::Url::JSON',
    
    # this is for 'do the right theme'
    dtrt => 'Praux::Url::DoTheRightTheme',
    
    # this is to show the right provisioner emblem
    emblem => 'Praux::Url::ProvisionerEmblem',
    
    # themes
    upload_theme => 'Praux::Url::UploadTheme',
    set_default_theme => 'Praux::Url::SetDefaultTheme',
    
    # deserializer
    import_resume => 'Praux::Url::ImportResume',
    
    # rssssss
    rss => 'Praux::Url::RSS',
    atom => 'Praux::Url::Atom',
    
    # mail mask..
    mm => 'Praux::Url::MailMask',
    
    # i made a bunch of aliases for these.
    pt => 'Praux::Tools::Hub',
    PrauxTools => 'Praux::Tools::Hub',
    praux_tools => 'Praux::Tools::Hub',
    prauxtools => 'Praux::Tools::Hub',
    
    # OpenID
    id => 'Praux::Url::OpenID',
    
    # new registration!
    r1 => 'Praux::Url::RegisterOne',
    r2 => 'Praux::Url::RegisterTwo',
    
    # disguise what this really does ;)
    bcards => 'Praux::Url::PDFPage',
    
    # QRcode
    qrcode => 'Praux::Url::QRcode',
    qrc => 'Praux::Url::QRcode',

    # facebook integration
    fb2praux => 'Praux::Url::FacebookToPrauxLogin',
    fbpostauth => 'Praux::Url::FacebookAuth',
    fb_create_resume => 'Praux::Url::FacebookCreateResume',
    
    # rr, new resume renderer...
    rr => 'Praux::Url::RenderResume',
    resume => 'Praux::Url::RenderResume',
);

my @instance_blacklist = qw/
    michael daren admin sysop prauxfessor help example test greg caryn
    joe tommy sean dana ted anthony tony mark marc erik brian bryan
    jimmy james george geoff jeff chris christopher fuck shit damn ass cunt slut
    whore chuck charles chery chucky david dave mike erin gary gerald gregory
    james jay jill john letty leticia lindsay larissa mom dad grandma grandpa
    martin marty miles matt matthew mia nick patty patricia phil rob robert rudy
    ryan samantha sam samuel sarah shannon shelley shelly stephanie tanya
    vera victoriana lisa betsy elizabeth mary patrick allyson allison ally 
    adam stephen steve kate kathleen katy toby tobyn
/;

# BUILD stop list (for the serialze, tokenize, stem (sts))
my %stop_hash;
my @stop_words = qw/i in a to the it have haven't was but is be from been try tried tought by our -
for test then how those their suit up which come own also and over take while with per great between
would of as an on that or act praux you click your right this see edit when can left remove make
'add' has choose even are here! it! item! summarize chance example way points few very all will bullet 
to...' what tip text select clicking 'edit' set sure 'delete' 'left you're get! sections! delete examples!
resume! sub-items my am job at they well far currently new including ensure indicators con de la en las al
y por assure me entire selecting add such had tip these using better further benefit del el para los una
como es experiencia include both gpa each locations location based e made make get work type embarrassing
company daily materials 
/;

foreach my $word (@stop_words) {
    $stop_hash{$word}++;
}
# END BUILD stop list

sub handle_request {
    my ($self, $romeo, @uri) = @_;

    # get rid of the "Praux" that was put here for run_extension()
    shift(@uri);

    if ($uri[$#uri] eq "robots.txt") {
        # no robots on dev!
        if ($self->is_dev) {
            $self->romeo->r->content_type('text/plain');
            print "User-agent: *\n";
            print "Disallow: /\n";
            return OK;
        } else {
            $self->romeo->r->content_type('text/plain');
            print "User-agent: *\n";
            if ($self->resume) {
                print "Sitemap: http://" . $self->resume->instance . ".praux.com/sitemap.xml\n";
            } else {
                print "Sitemap: http://praux.com/sitemap.xml\n";
            }
            return OK;
        }
    } elsif ($uri[$#uri] eq "sitemap.xml") {
        return $self->romeo->run_extension('Praux::Url::Sitemap', @uri);
    }

    my $function = shift(@uri);

    # we will derive language context here in the future.  for now, it's the resume's default language
    $romeo->param('language_context', 'en');

    foreach my $bl (@instance_blacklist) {
        if ($bl eq $self->instance) {
            # we're blacklisted..  just redir them back to the site proper.
            $romeo->r->headers_out->set(Location => $self->root_url);
            return REDIRECT;
        }
    }

    # always run extensions for all urls.
    if (exists($urlc_map{$function})) {
        # set the front end..
        return $self->romeo->run_extension($urlc_map{$function}, @uri);
    }

    if ($self->instance eq "www" || $self->instance eq "ssl" || $self->instance eq "") {
        $self->romeo->r->content_type('text/html;charset=utf-8;charset=utf-8');
        $self->romeo->render_page('index', { self => $self });
    } else {
        if ($self->resume) {
            # render / cache resume!
            return $self->romeo->run_extension('Praux::Url::RenderResume', $function, @uri);
        } else {
            $self->romeo->r->content_type('text/html;charset=utf-8');
            $self->romeo->render_page('empty_resume', { self => $self });
        }
    }

    return OK;
}

sub search_resumes_paged {
    my ($self, $query, $page, $order_by, $sort_order, $rows) = @_;
    
    $rows = 15 unless $rows;
    
    # determine what we're giving back and in what order!
    if ($order_by) {
        $order_by = "$order_by $sort_order";
    } else {
        $order_by = "create_time DESC";
    }
    
    my $results = $self->schema->resultset('Resume')->search_rs(
        {
            -or => [
                address => { like => '%' . $query . '%' },
                email => { like => '%' . $query . '%' },
                name => { like => '%' . $query . '%' },
                phone => { like => '%' . $query . '%' },
                instance => { like => '%' . $query . '%' },
                'content_items.body' => { like => '%' . $query . '%' },
                'content_items.title' => { like => '%' . $query . '%' },
                'content_items.instructor' => { like => '%' . $query . '%' },
                'content_items.role', { like => '%' . $query . '%' },
                'content_items.locality', { like => '%' . $query . '%' },
                'content_items.organization', { like => '%' . $query . '%' },
                'content_items.date_range', { like => '%' . $query . '%' },
            ],
        },
        {
            join => 'content_items',
            order_by => $order_by,
            group_by => 'me.id',
            rows => $rows,
            page => $page ? $page : 1,
        },
    );
    
    return $results;
}

sub recently_updated_resumes {
    my ($self, $page, $rows) = @_;
    $rows = 15 unless $rows;
    return $self->schema->resultset('Resume')->search(
        {
            completeness => { '>=' => 90 },
        },
        {
            order_by => "modify_time DESC",
            rows => $rows,
            page => $page ? $page : 1,
        }
    );
}

sub recently_updated_resumes_with_gravatars {
    my ($self, $page, $rows) = @_;
    $rows = 15 unless $rows;
    $page = $page ? $page : int(rand(5));

    return $self->schema->resultset('Resume')->search(
        {
            completeness => { '>=' => 70 },
            'praux_user.gravatar_url' => { '!=', undef },
        },
        {
            order_by => "modify_time DESC",
            join => 'praux_user',
            rows => $rows,
            page => $page ? $page : 1,
        }
    );
}

sub recently_completed_resumes {
    my ($self, $page, $rows) = @_;
    $rows = 15 unless $rows;
    return $self->schema->resultset('Resume')->search(
        {
            completeness => { '>=' => 90 },
        },
        {
            order_by => "create_time DESC",
            rows => $rows,
            page => $page ? $page : 1,
        }
    );
}

sub all_resumes_paged {
    my ($self, $page, $order_by, $sort_order, $rows) = @_;
    
    $rows = 15 unless $rows;
    
    # determine what we're giving back and in what order!
    if ($order_by) {
        $order_by = "$order_by $sort_order";
    } else {
        $order_by = "create_time DESC";
    }
    
    return $self->schema->resultset('Resume')->search_rs(undef,
        {
            order_by => $order_by,
            rows => $rows,
            page => $page ? $page : 1,
        }
    );
}

sub root_url {
    my ($self) = @_;
    if ($self->is_dev) {
        return "http://prauxdev.com";
    } else {
        if ($self->instance eq "ssl") {
            return "https://ssl.praux.com";
        } else {
            return "http://praux.com";
        }
    }
}

sub is_blocked_browser {
    my ($self) = @_;
    my $ua = $self->romeo->user_agent;
    if ($ua =~ /MSIE/o && ($ua !~ /8\.0/o && $ua !~ /chromeframe/o)) {
        return 1;
    }
    return undef;
}

sub is_myself {
    my ($self) = @_;
    
    if ($self->romeo->r->connection->remote_ip =~ /^216\.150\.225\./) {
        return 1;
    }
}

# use empty labels instead ;)
sub empty_labels {
    my ($self, $lang) = @_;
    if (my $resume = $self->resume) {
        my $lang = $self->lang unless $lang;
        my $tc = $self->romeo->tc->{pyaml}->{empty_labels};
        if (exists($tc->{$lang})) {
            return $tc->{$lang};
        } else {
            warn "Lang: $lang doesn't exist in empty labels!  Get to work, translators!\n";
        }
    }
    return $self->romeo->tc->{pyaml}->{empty_labels};
}

sub get_cache {
    my ($self) = @_;
    if (my $cached = $self->memd->get($self->romeo->instance)) {
        return $cached;
    }
    return {};
}

sub set_cache {
    my ($self, $to_cache) = @_;
    $self->memd->set($self->romeo->instance, $to_cache, 1209600);
}

sub clear_all_cache {
    my ($self) = @_;
    $self->memd->remove($self->romeo->instance) if $self->romeo;
}

sub memd {
    return $memd;
}

sub pretty_date {
    my ($self, $epoch) = @_;
    return strftime('%A, %B %d at %r', localtime($epoch));
}

sub pretty_date_with_year {
    my ($self, $epoch) = @_;
    return strftime('%A, %B %d %Y at %r', localtime($epoch));
}

sub css_file {
    my ($self) = @_;
    return undef;
}

sub referrer_rank {
    my ($self, $user) = @_;
    $user = $user->id if ref($user);
    my $top = $self->top_referrers;
    $i = 0;
    foreach my $referrer (sort { $top->{$b} <=> $top->{$a} } keys %$top) {
        $i++;
        if ($referrer == $user) {
            if ($i =~ /11$/) {
                return $i . "th";
            } elsif ($i =~ /12$/) {
                return $i . "th";
            } elsif ($i =~ /13$/) {
                return $i . "th";
            } elsif ($i =~ /1$/) {
                return $i . "st";
            } elsif ($i =~ /2$/) {
                return $i . "nd";
            } elsif ($i =~ /3$/) {
                return $i . "rd";
            } else {
                return $i . "th";
            }
        }
    }
    return undef;
}

sub referrer_rank_march_2010 {
    my ($self, $user) = @_;
    $user = $user->id if ref($user);
    my $top = $self->top_referrers_march_2010;
    $i = 0;
    foreach my $referrer (sort { $top->{$b} <=> $top->{$a} } keys %$top) {
        $i++;
        if ($referrer == $user) {
            if ($i =~ /11$/) {
                return $i . "th";
            } elsif ($i =~ /12$/) {
                return $i . "th";
            } elsif ($i =~ /13$/) {
                return $i . "th";
            } elsif ($i =~ /1$/) {
                return $i . "st";
            } elsif ($i =~ /2$/) {
                return $i . "nd";
            } elsif ($i =~ /3$/) {
                return $i . "rd";
            } else {
                return $i . "th";
            }
        }
    }
    return undef;
}

sub top_referrers {
    my ($self) = @_;
    return $self->report->top_referrers(time - (3600 * 24 * 30), time, 100);
}

sub valid_referrals {
    my ($self, $user) = @_;
    $user = $user->id if ref($user);
    return $self->top_referrers->{$user} or 0;
}

sub valid_referrals_march_2010 {
    my ($self, $user) = @_;
    $user = $user->id if ref($user);
    return $self->top_referrers_march_2010->{$user};
}

# convenience.. hard coded values for the iPod competition!
sub top_referrers_march_2010 {
    my ($self) = @_;
    my $lower = 1267457199;
    my $upper = 1270049224;
    my $count = 100;
    return $self->report->top_referrers($lower, $upper, $count);
}

sub report {
    my ($self) = @_;
    return Praux::Report->new($self);
}

sub is_mine {
    my ($self) = @_;
    if (my $user = $self->active_user) {
        if ($user->id == $self->resume->praux_user->id) {
            return 1;
        }
    }
    return undef;
}

sub active_user_gravatar {
    my ($self) = @_;
    if ($self->active_user) {
        $self->gravatar($self->active_user->email);
    } else {
        return undef;
    }
}

# check to see if this email has a gravatar!
sub gravatar_exists {
    my ($self, $email) = @_;
    my $ua = new LWP::UserAgent;
    $ua->agent('Praux Resumes v' . $VERSION);
    
    my $resp = $ua->get($self->gravatar_url($email) . "?d=404");
    
    if ($resp->code == 200) {
        return 1;
    }
    
    return undef;
}

sub gravatar_url {
    my ($self, $email) = @_;
    return "http://www.gravatar.com/avatar/" . md5_hex(lc($email)) . ".jpg";
}

# finds all views for a certain node.
sub find_views {
    my ($self, $node, $views, $depth) = @_;
    
    $views = [] unless $views;
    
    # if this node has views, we're done.
    if (!$depth && ($node->view_names && scalar(@{$node->view_names}))) {
        return $node->view_names;
    } elsif ($node->view_names) {
        push(@$views, @{$node->view_names});
    }

    # otherwise, we need to recurse upwards. (section headers can't have parents!)
    if ($node->parent) {
        push(@$views, @{$self->find_views($node->parent, $views, $depth + 1)});
        return $views;
    } else {
        # inherit the section's views..
        push(@$views, @{$node->section->view_names});
        if (scalar(@$views) > 0) {
            # default is always implied, unless explicitly removed.
            my $has_default = 0;
            foreach my $v (@$views) {
                if (lc($v) eq "default") {
                    $has_default = 1;
                }
            }
            if ($has_default) {
                return $views;
            } else {
                return [@$views, 'default'];
            }
        } else {
            return ['default'];
        }
    }
}

# simple method that returns true if a node has a certain view.
sub has_view {
    my ($self, $node, $view) = @_;

    unless ($view) {
        if ($self->{view}) {
            $view = $self->{view};
        } else {
            $view = "default";
        }
    }

    # everyone has the "all" view ;)
    return 1 if $view eq "all";
    
    # all view is the same as the edit view, but with the helper
    return 1 if $view eq "edit";
    
    my $check_array;
    if (ref($node) eq "Praux::DB::Resume::Section") {
        $check_array = $node->view_names;
        
        # we always rep the default.  good find, mikey g.
        unless ($check_array && scalar(@$check_array)) {
            $check_array = ['default'];
        }
    } else {
        $check_array = $self->find_views($node);
    }

    foreach my $check_view (@$check_array) {
        if (lc($view) eq lc($check_view)) {
            return 1;
        }
    }
    return undef;
}

sub instance {
    my ($self) = @_;
    my @ic = split(/\./, $self->romeo->instance);
    return join('.', @ic[0..$#ic-2]);
}

# also for backwards compat
sub open_db {
    my ($self) = @_;
    unless ($self->{dbh}) {
        $self->{dbh} = DBI->connect($self->c->DSN, $self->c->DB_USER, $self->c->DB_PASS);
    }
    return $self->{dbh};
}

sub import_yaml_resume {
    my ($self, $yaml, $instance) = @_;
    my $resume = $self->resume_by_instance($instance);
    if ($resume) {
        $resume->clear;
        $self->load_yaml_at($yaml, $resume);
    } else {
        die "Error: Target resume must exist for import.  $instance" . $self->cookie_domain . " not found.\n";
    }
    $self->clear_all_cache();
}

# ok serialize operations..
sub load_yaml_at {
    my ($self, $yaml, $target) = @_;
    my $data;
    eval {
        $data = Load($yaml);
    };
    
    if (my $error = $@) {
        die "YAML Load Error: $error\n";
    }
    
    if ($data) {
        if ($data->{sections}) {
            # get our resume.
            my $resume;
            if (ref($target)) {
                $resume = $target;
            } else {
                $resume = $self->resume_by_instance($target);
            }
            
            foreach my $method (qw/address email name phone/) {
                $resume->$method($data->{$method}) if $data->{$method};
            }
            $resume->update;
            
            # we have sections, can't load a section at a location.
            foreach my $hr (@{$data->{sections}}) {
                my $sec = $self->schema->resultset('Resume::Section')->create(
                    {
                        format => $hr->{format},
                        sort_order => $hr->{sort_order},
                        resume => $resume->id,
                    }
                );
                
                # add the views!
                foreach my $view (@{$hr->{views}}) {
                    $self->schema->resultset('Resume::View')->create(
                        {
                            resume => $sec->resume->id,
                            section => $sec->id,
                            view_name => $view,
                            owner => $sec->resume->praux_user->id,
                        }
                    );
                }
                
                # just the first one.. cos its the section header.
                $self->load_cb($hr->{content_blocks}->[0], $sec);
            }
            
        } else {
            # ok.  we need content blocks here.
            my $cb;
            if (ref($target)) {
                $cb = $target;
            } else {
                $cb = $self->cb($target);
            }
            
            # this is a flat ContentItem load
            if (exists($data->{submitter})) {
                # load this content item directly into this block.
                $data->{content_block} = $cb->id;
                
                # allow a load action to overrule previous visibility.
                if ($data->{visible} == 1 && $cb->visible_item) {
                    my $vi = $cb->visible_item;
                    $vi->visible(0);
                    $vi->update;
                }
                $data->{resume} = $cb->resume->id;
                $self->schema->resultset('Resume::ContentItem')->create($data);
            } elsif (exists($data->{content_items})) {
                # this is a content block.
                $self->load_cb($data, $cb);
            }
        }
    } else {
        die "YAML Load Error: no data found!\n";
    }
    
    $self->clear_all_cache();
}

# recursive generic data to content block loader.
sub load_cb {
    my ($self, $data, $parent) = @_;
    
    my $cb;
    if (ref($parent) eq "Praux::DB::Resume::Section") {
        $cb = $self->schema->resultset('Resume::ContentBlock')->create(
            {
                resume => $parent->resume->id,
                section => $parent->id,
                format => $data->{format},
                sort_order => $data->{sort_order},
            }
        );
    } else {    
        $cb = $self->schema->resultset('Resume::ContentBlock')->create(
            {
                section => $parent->section->id,
                resume => $parent->resume->id,
                parent => $parent->id,
                format => $data->{format},
                sort_order => $data->{sort_order},
            }
        );
    }
    
    if ($cb) {
        # add the views!
        foreach my $view (@{$data->{views}}) {
            $self->schema->resultset('Resume::View')->create(
                {
                    resume => $cb->section->resume->id,
                    content_block => $cb->id,
                    view_name => $view,
                    owner => $cb->section->resume->praux_user->id,
                }
            );
        }
    }
    
    foreach my $hr (@{$data->{content_items}}) {
        $hr->{content_block} = $cb->id;
        $hr->{resume} = $cb->resume->id;
        $self->schema->resultset('Resume::ContentItem')->create($hr);
    }
    
    # be there children?
    if ($data->{children}) {
        foreach my $child (@{$data->{children}}) {
            $self->load_cb($child, $cb);
        }
    }
}

sub schema {
    my ($self) = @_;
    unless (defined($self->{schema})) {
        $self->{schema} = Praux::DB->connect($self->c->DSN, $self->c->DB_USER, $self->c->DB_PASS);
    }
    return $self->{schema};
}

sub active_user {
    my ($self) = @_;
    if ($self->session && (my $user = $self->session->praux_user)) {
        return $user;
    } else {
        return undef;
    }
}

sub request {
    return Apache2::RequestUtil->request;
}

sub log_error {
    my ($self, $error) = @_;
    if (my $r = $self->request) {
        # apache error log...
        $r->log_error($error);
    } else {
        # stderr
        warn $error;
    }
}

sub log_action {
    my ($self, $data) = @_;
    return $self->schema->resultset('Log')->create($data);
}

sub resume_url {
    my ($self) = @_;
    return $self->romeo->app_base;
}

sub this_url {
    my ($self) = @_;
    return $self->resume_url . "/" . $self->view . "/" . $self->lang . "/";
}

sub provisioner_by_id {
    my ($self, $id) = @_;
    return $self->schema->resultset('Provisioner')->find(
        {
            id => $id,
        }
    );
}

sub provisioner_by_hash {
    my ($self, $hash) = @_;
    return $self->schema->resultset('Provisioner')->find(
        {
            provision_hash => $hash,
        }
    );
}

sub global_theme_by_name {
    my ($self, $name) = @_;
    return $self->schema->resultset('Resume::Theme')->search(
        {
            theme_name => $name,
            deploy_type => 'global',
        }
    )->first;
}

sub theme_by_id {
    my ($self, $id) = @_;
    return $self->schema->resultset('Resume::Theme')->single({ id => $id });
}

# making this a bit more intelligent for the new subweb context..
sub resume {
    my ($self) = @_;
    
    my $resume;
    unless ($resume = $self->resume_by_instance($self->instance)) {
        # derive resume by location
        my $uri = $self->romeo->r->uri;
        if ($uri =~ /(?:resume|rr)\/([\w\-\.]+)\//) {
            $resume = $self->resume_by_instance($1);
        }
        
        unless ($resume) {
            # derive resume by referrer
            my $referrer = $self->romeo->r->headers_in->get('Referer');
            if ($referrer =~ /(?:resume|rr)\/([\w\-\.]+)\//) {
                $resume = $self->resume_by_instance($1);
            }
        }
    }
    
    return $resume;
}

sub suggestion {
    my ($self, $id) = @_;
    return $self->schema->resultset('Resume::ContentItem::Suggestion')->single({id => $id});
}

sub cb {
    my ($self, $id) = @_;
    return $self->schema->resultset('Resume::ContentBlock')->single({id => $id});
}

sub ci {
    my ($self, $id) = @_;
    return $self->schema->resultset('Resume::ContentItem')->single({id => $id});
}

sub sec {
    my ($self, $id) = @_;
    return $self->schema->resultset('Resume::Section')->single({id => $id});
}

sub resume_by_id {
    my ($self, $id) = @_;
    return $self->schema->resultset('Resume')->find(
        {
            id => $id,
        }
    );
}

sub resume_by_instance {
    my ($self, $instance) = @_;
    return $self->schema->resultset('Resume')->search(
        {
            instance => $instance,
        }
    )->first;
}

sub user_by_id {
    my ($self, $id) = @_;
    return $self->schema->resultset('User')->find(
        {
            id => $id,
        }
    );
}

sub user_by_verify_token {
    my ($self, $token) = @_;
    return $self->schema->resultset('User')->search(
        {
            verify_token       =>      $token,
        }
    )->first;
}

sub active_user_by_email {
    my ($self, $email) = @_;
    return $self->schema->resultset('User')->search(
        {
            email       =>      $email,
            active      =>      1,
        }
    )->first;
}

sub user_by_email {
    my ($self, $email) = @_;
    return $self->schema->resultset('User')->search(
        {
            email       =>      $email,
        }
    )->first;
}

sub search {
    my ($self, $search_string) = @_;
    
    # ok.. 
    
}

sub global_themes {
    my ($self) = @_;
    return $self->schema->resultset('Resume::Theme')->search(
        {
            deploy_type => 'global',
        }
    )->all;
}

# truncate:
# takes 3 arguments, 2 required one optional
# they are: the data to truncate
# the length of the truncated value, and a boolean
# value for wether or not we're going to break at the end of a word
sub truncate {
    my ($self, $data, $len, $bow) = @_;

    # return data if the length of all the data is less than the length
    if (length($data) < $len) {
        return $data;
    }

    if ($bow) {
        # we're going to strip out html and formatting, and replace it with whitespace.  This should do the trick..
        $data =~ s/\<[\\A-Za-z0-9\/\=\"\'\s\_\-\?\!\.\&:;]+\>/ /og;

        # prepare the return value...
        my $return_value;
        my @words = split(/\s+/, $data);
        my $word = 1;
        $return_value = $words[0];

        # add words until we exceed the specified length or run out of words
        while (length($return_value) < $len) {
            $return_value .= " $words[$word]";
            last if $word == $#words;
            ++$word;
        }

        # and return! (w/ yadda yadda yadda)
        return $return_value . "";
    } else {
        return substr($data, 0, $len);
    }
}

sub time {
    return time;
}

sub mailer {
    my ($self) = @_;
    
    my $from = $self->c->ADMIN_EMAIL ? $self->c->ADMIN_EMAIL : 'sysop@praux.com';
    
    $Mail::Sender::NO_X_MAILER = 1;
    
    my $mailer = Mail::Sender->new(
        {    
            smtp        =>      'mail.mg2.org',
            from        =>      $from,
            headers     =>      {
                'X-Mailer'      =>      'Praux v' . $Praux::VERSION,
            }
        }
    );
    
    return $mailer;
}

sub is_dev {
    my ($self) = @_;
    return $self->romeo->c->IS_DEVELOPMENT;
}

sub cookie_domain {
    my ($self) = @_;
    return $self->romeo->c->COOKIE_DOMAIN if $self->romeo;
}

sub anonymous_user {
    my ($self) = @_;
    return $self->user_by_email('Anonymous');
}

# just rebless the bN session...
sub session {
    my ($self) = @_;

   if ($self->romeo && $self->romeo->session) {
        return bless ($self->romeo->session, 'Praux::Session');
    } else {
        return undef;
    }
}

# new uuid
sub new_uuid {
    my ($self) = @_;
    return $ug->create_str;
}

sub version {
    my ($self) = @_;
    return $VERSION;
}

sub lang_short_to_long {
    my ($self, $lang) = @_;
    $lang = $self unless ref($self);
    my $lang_hash = {
        'de' => 'Deutsch',
        'ne' => 'Nepali',
        'tr' => 'Turkish',
        'ki' => 'Kikuyu',
        'da' => 'Dansk',
        'ug' => 'Uighur',
        'gl' => 'Galician',
        'tn' => 'Tswana',
        'fr' => 'Français',
        'ta' => 'தமிழ்',
        'co' => 'Corsican',
        'rw' => 'Kinyarwanda',
        'br' => 'Breton',
        'st' => 'Sotho, Southern',
        'ko' => '한국어',
        'ak' => 'Akan',
        'ps' => 'Pushto',
        'km' => 'Central Khmer',
        'av' => 'Avaric',
        'af' => 'Afrikaans',
        'qu' => 'Quechua',
        'ti' => 'Tigrinya',
        'mt' => 'Maltese',
        'ky' => 'Kirghiz',
        'la' => 'Latin',
        'ga' => 'Irish',
        'bh' => 'Bihari languages',
        'oc' => 'Occitan (post 1500)',
        'sv' => 'svenska',
        'it' => 'Italiano',
        'hu' => 'Hungarian',
        'za' => 'Zhuang',
        'ng' => 'Ndonga',
        'dv' => 'Divehi',
        'se' => 'Northern Sami',
        'lu' => 'Luba-Katanga',
        'kv' => 'Komi',
        'jv' => 'Javanese',
        've' => 'Venda',
        'na' => 'Nauru',
        'pt' => 'Portuguese',
        'ks' => 'Kashmiri',
        'hi' => 'हिन्दी',
        'mh' => 'Marshallese',
        'ba' => 'Bashkir',
        'kg' => 'Kongo',
        'no' => 'Norwegian',
        'lv' => 'Latvian',
        'os' => 'Ossetian',
        'ho' => 'Hiri Motu',
        'ln' => 'Lingala',
        'id' => 'Indonesian',
        'sr' => 'Српски',
        'si' => 'Sinhala',
        'vo' => 'Volapük',
        'ff' => 'Fulah',
        'om' => 'Oromo',
        'ab' => 'Abkhazian',
        'fi' => 'Finnish',
        'fj' => 'Fijian',
        'wo' => 'Wolof',
        'sn' => 'Shona',
        'li' => 'Limburgan',
        'sd' => 'Sindhi',
        'yi' => 'Yiddish',
        'ii' => 'Sichuan Yi',
        'gv' => 'Manx',
        'ha' => 'Hausa',
        'lg' => 'Ganda',
        'pa' => 'Panjabi',
        'sl' => 'Slovenščina',
        'am' => 'Amharic',
        'mr' => 'Marathi',
        'bi' => 'Bislama',
        'ee' => 'Ewe',
        'kj' => 'Kuanyama',
        'rm' => 'Romansh',
        'dz' => 'Dzongkha',
        'kn' => 'Kannada',
        'rn' => 'Rundi',
        'eo' => 'Esperanto',
        'fy' => 'Western Frisian',
        'mn' => 'Mongolian',
        'ik' => 'Inupiaq',
        'nv' => 'Navajo',
        'gd' => 'Gaelic',
        'as' => 'Assamese',
        'ae' => 'Avestan',
        'tk' => 'Turkmen',
        'mg' => 'Malagasy',
        'su' => 'Sundanese',
        'sc' => 'Sardinian',
        'ru' => 'Русский',
        'ia' => 'Interlingua',
        'nb' => 'Bokmål',
        'cr' => 'Cree',
        'ku' => 'Kurdish',
        'vi' => 'Tiếng Việt',
        'az' => 'Azerbaijani',
        'lo' => 'Lao',
        'sg' => 'Sango',
        'bm' => 'Bambara',
        'aa' => 'Afar',
        'lb' => 'Luxembourgish',
        'nr' => 'Ndebele',
        'ts' => 'Tsonga',
        'kw' => 'Cornish',
        'ml' => 'Malayalam',
        'uz' => 'Uzbek',
        'ht' => 'Haitian',
        'kl' => 'Kalaallisut',
        'bs' => 'Bosnian',
        'iu' => 'Inuktitut',
        'yo' => 'Yoruba',
        'to' => 'Tonga',
        'cu' => 'Church Slavic',
        'ch' => 'Chamorro',
        'wa' => 'Walloon',
        'bg' => 'Български',
        'gu' => 'Gujarati',
        'ca' => 'Catalan',
        'pl' => 'Polski',
        'ay' => 'Aymara',
        'oj' => 'Ojibwa',
        'ty' => 'Tahitian',
        'an' => 'Aragonese',
        'uk' => 'Українська',
        'es' => 'Español',
        'sw' => 'Swahili',
        'kr' => 'Kanuri',
        'tt' => 'Tatar',
        'fo' => 'Faroese',
        'ss' => 'Swati',
        'or' => 'Oriya',
        'sa' => 'Sanskrit',
        'xh' => 'Xhosa',
        'io' => 'Ido',
        'th' => 'ภาษาไทย',
        'ie' => 'Interlingue',
        'et' => 'Estonian',
        'so' => 'Somali',
        'tl' => 'Tagalog',
        'nd' => 'Ndebele, North',
        'en' => 'English',
        'ta' => 'தமிழ',
        'lt' => 'Lithuanian',
        'hr' => 'Croatian',
        'gn' => 'Guarani',
        'be' => 'Belarusian',
        'zu' => 'Zulu',
        'ur' => 'Urdu',
        'cv' => 'Chuvash',
        'tw' => 'Twi',
        'hz' => 'Herero',
        'ce' => 'Chechen',
        'nn' => 'Norsk',
        'bn' => 'Bengali',
        'ja' => '日本語',
        'tg' => 'Tajik',
        'pi' => 'Pali',
        'te' => 'Telugu',
        'iw' => 'עברית',
        'ig' => 'Igbo',
        'ar' => 'العربية',
        'sm' => 'Samoan',
        'ny' => 'Chichewa',
        'kk' => 'Kazakh',
        'zh' => '中文(简体)',
        'el' => 'Ελληνικά',
        'pt-br' => 'Português (Brasil)',
        'pt-pt' => 'Português (Portugal)',
    };
    
    return $lang_hash->{lc($lang)};
}

sub lang_short_to_long_en {
    my ($self, $lang) = @_;
    $lang = $self unless ref($self);
    my $lang_hash = {
        'de' => 'German',
        'ne' => 'Nepali',
        'tr' => 'Turkish',
        'ki' => 'Kikuyu',
        'da' => 'Danish',
        'ug' => 'Uighur',
        'gl' => 'Galician',
        'tn' => 'Tswana',
        'fr' => 'French',
        'ta' => 'Tamil',
        'co' => 'Corsican',
        'rw' => 'Kinyarwanda',
        'br' => 'Breton',
        'st' => 'Sotho, Southern',
        'ko' => 'Korean',
        'ak' => 'Akan',
        'ps' => 'Pushto',
        'km' => 'Central Khmer',
        'av' => 'Avaric',
        'af' => 'Afrikaans',
        'qu' => 'Quechua',
        'ti' => 'Tigrinya',
        'ta' => 'Tamil',
        'mt' => 'Maltese',
        'ky' => 'Kirghiz',
        'la' => 'Latin',
        'ga' => 'Irish',
        'bh' => 'Bihari languages',
        'oc' => 'Occitan (post 1500)',
        'sv' => 'Swedish',
        'it' => 'Italian',
        'hu' => 'Hungarian',
        'za' => 'Zhuang',
        'ng' => 'Ndonga',
        'dv' => 'Divehi',
        'se' => 'Northern Sami',
        'lu' => 'Luba-Katanga',
        'kv' => 'Komi',
        'jv' => 'Javanese',
        've' => 'Venda',
        'na' => 'Nauru',
        'pt' => 'Portuguese',
        'ks' => 'Kashmiri',
        'hi' => 'Hindi',
        'mh' => 'Marshallese',
        'ba' => 'Bashkir',
        'kg' => 'Kongo',
        'no' => 'Norwegian',
        'lv' => 'Latvian',
        'os' => 'Ossetian',
        'ho' => 'Hiri Motu',
        'ln' => 'Lingala',
        'id' => 'Indonesian',
        'sr' => 'Serbian',
        'si' => 'Sinhala',
        'vo' => 'Volapük',
        'ff' => 'Fulah',
        'om' => 'Oromo',
        'ab' => 'Abkhazian',
        'fi' => 'Finnish',
        'fj' => 'Fijian',
        'wo' => 'Wolof',
        'sn' => 'Shona',
        'li' => 'Limburgan',
        'sd' => 'Sindhi',
        'yi' => 'Yiddish',
        'ii' => 'Sichuan Yi',
        'gv' => 'Manx',
        'ha' => 'Hausa',
        'lg' => 'Ganda',
        'pa' => 'Panjabi',
        'sl' => 'Slovenian',
        'am' => 'Amharic',
        'mr' => 'Marathi',
        'bi' => 'Bislama',
        'ee' => 'Ewe',
        'kj' => 'Kuanyama',
        'rm' => 'Romansh',
        'dz' => 'Dzongkha',
        'kn' => 'Kannada',
        'rn' => 'Rundi',
        'eo' => 'Esperanto',
        'fy' => 'Western Frisian',
        'mn' => 'Mongolian',
        'ik' => 'Inupiaq',
        'nv' => 'Navajo',
        'gd' => 'Gaelic',
        'as' => 'Assamese',
        'ae' => 'Avestan',
        'tk' => 'Turkmen',
        'mg' => 'Malagasy',
        'su' => 'Sundanese',
        'sc' => 'Sardinian',
        'ru' => 'Russian',
        'ia' => 'Interlingua',
        'nb' => 'Bokmål',
        'cr' => 'Cree',
        'ku' => 'Kurdish',
        'vi' => 'Vietnamese',
        'az' => 'Azerbaijani',
        'lo' => 'Lao',
        'sg' => 'Sango',
        'bm' => 'Bambara',
        'aa' => 'Afar',
        'lb' => 'Luxembourgish',
        'nr' => 'Ndebele',
        'ts' => 'Tsonga',
        'kw' => 'Cornish',
        'ml' => 'Malayalam',
        'uz' => 'Uzbek',
        'ht' => 'Haitian',
        'kl' => 'Kalaallisut',
        'bs' => 'Bosnian',
        'iu' => 'Inuktitut',
        'yo' => 'Yoruba',
        'to' => 'Tonga',
        'cu' => 'Church Slavic',
        'ch' => 'Chamorro',
        'wa' => 'Walloon',
        'bg' => 'Bulgarian',
        'gu' => 'Gujarati',
        'ca' => 'Catalan',
        'pl' => 'Polish',
        'ay' => 'Aymara',
        'oj' => 'Ojibwa',
        'ty' => 'Tahitian',
        'an' => 'Aragonese',
        'uk' => 'Ukrainian',
        'es' => 'Spanish',
        'sw' => 'Swahili',
        'kr' => 'Kanuri',
        'tt' => 'Tatar',
        'fo' => 'Faroese',
        'ss' => 'Swati',
        'or' => 'Oriya',
        'sa' => 'Sanskrit',
        'xh' => 'Xhosa',
        'io' => 'Ido',
        'th' => 'Thai',
        'ie' => 'Interlingue',
        'et' => 'Estonian',
        'so' => 'Somali',
        'tl' => 'Tagalog',
        'nd' => 'Ndebele, North',
        'en' => 'English',
        'lt' => 'Lithuanian',
        'hr' => 'Croatian',
        'gn' => 'Guarani',
        'be' => 'Belarusian',
        'zu' => 'Zulu',
        'ur' => 'Urdu',
        'cv' => 'Chuvash',
        'tw' => 'Twi',
        'hz' => 'Herero',
        'ce' => 'Chechen',
        'nn' => 'Norwegian Nynorsk',
        'bn' => 'Bengali',
        'ja' => 'Japanese',
        'tg' => 'Tajik',
        'pi' => 'Pali',
        'te' => 'Telugu',
        'iw' => 'Hebrew',
        'ig' => 'Igbo',
        'ar' => 'Arabic',
        'sm' => 'Samoan',
        'ny' => 'Chichewa',
        'kk' => 'Kazakh',
        'zh' => 'Chinese',
        'el' => 'Greek',
        'pt-br' => 'Portuguese (Brazil)',
        'pt-pt' => 'Portuguese (Portugal)',
    };
    
    return $lang_hash->{lc($lang)};
}

sub serialize_text {
    my ($self, $resume, $view, $lang) = @_;
    $resume = $self->resume unless ref($resume);
    
    return undef unless $resume;
    
    # 80 column resume!
    $Text::Wrap::columns = 80;
    
    my $text;
    
    if ($self->resume->praux_user->preference('com.praux.anonymize_resume')) {
        $text .= "An Excellent Candidate\n";
    } else {
        # thank you, thank you very much...
        if ($resume->address) {
            $text .= sprintf("%-38s  %-38s\n", substr($resume->name, 0, 38), substr($resume->address, 0, 38));
        } else {
            $text .= sprintf("%-80s\n", substr($resume->name, 0, 80));
        }

        if ($resume->phone) {
            $text .= sprintf("%-38s  %-38s\n", substr($resume->email, 0, 38), substr($resume->phone, 0, 38));
        } else {
            $text .= sprintf("%-80s\n", substr($resume->email, 0, 80));
        }
    }

    $text .= "\n";

    foreach my $section ($resume->sorted_sections) {
        # skip ones that aren't in this view!
        next unless $self->has_view($section, $view);

        # get the section header content block!
        my $sec_cb = $section->header_cb;
        
        # no visible item for this language in this block!  Skip!
        next unless $sec_cb->visible_item($lang);
        my $section_header = $sec_cb->visible_item($lang)->body or "Section Name";
        $text .= sprintf("%-80s\n", $section_header);
        $text .= "-" x 80 . "\n";

        my $count = $sec_cb->children->count;
        my $i;
        foreach my $cb ($sec_cb->sorted_children) {
            next unless $self->has_view($cb, $view);
            my $vi = $cb->visible_item($lang);
            next unless $vi; # no visible item, no render.
            $i++;
            if ($cb->format eq "generic") {
                $self->add_generic($cb, 0, \$text);
            } elsif ($cb->format eq "generic_nobullets") {
                $self->add_generic_nobullets($cb, 0, \$text);
            } elsif ($cb->format eq "job") {
                $text .= sprintf("%-15s      %-25s      %28s\n", substr($vi->date_range ? $vi->date_range : "MM/DD", 0, 15),
                                                        substr($vi->organization ? $vi->organization : "Company Name", 0, 25),
                                                        substr($vi->locality ? $vi->locality : "City, ST", 0, 28));
                $text .= sprintf("                     %-60s\n", substr($vi->title ? $vi->title : "Title", 0, 60));
                foreach my $child ($cb->sorted_children) {
                    next unless $self->has_view($child, $view);
                    $self->add_generic($child, 0, \$text);
                }
                $text .= "\n" unless $i == $count;
            } elsif ($cb->format eq "project") {
                $text .= sprintf("%-15s      %-25s      %28s\n", substr($vi->date_range ? $vi->date_range : "MM/DD", 0, 15),
                                                        substr($vi->title ? $vi->title : "Project Name", 0, 25),
                                                        substr($vi->locality ? $vi->locality : "City, ST", 0, 28));
                $text .= sprintf("                     %-60s\n", substr($vi->organization ? $vi->organization : "Organization" . 
                                                        " - " . $vi->role ? $vi->role : "Project Role", 0, 60));
                foreach my $child ($cb->sorted_children) {
                    next unless $self->has_view($child, $view);
                    $self->add_generic($child, 0, \$text);
                }
                $text .= "\n" unless $i == $count;
            } elsif ($cb->format eq "course") {
                $text .= sprintf("%-15s      %-25s      %28s\n", substr($vi->date_range ? $vi->date_range : "MM/DD", 0, 15),
                                                        substr($vi->title ? $vi->title : "Course Name", 0, 25),
                                                        substr($vi->locality ? $vi->locality : "City, ST", 0, 28));
                $text .= sprintf("                     %-60s\n", substr($vi->instructor ? $vi->instructor : "Instructor", 0, 60));
                foreach my $child ($cb->sorted_children) {
                    next unless $self->has_view($child, $view);
                    $self->add_generic($child, 0, \$text);
                }
                $text .= "\n" unless $i == $count;
            }
        }
        $text .= "\n\n";
    }
    
    return $text;
}

# supplemental for text serializer
sub add_generic {
    my ($self, $cb, $depth, $textref) = @_;
    
    # unpack these lil tidbits ;)
    my $lang = $self->lang;
    my $view = $self->view;
    
    my $vi = $cb->visible_item($lang);
    if ($vi) {
        my $body = $vi->body;
        $$textref .= wrap("    " x $depth . " * ", '', $body) . "\n";
    } else {
        $$textref .= wrap("    " x $depth . " * ", '', $self->empty_labels($lang)->{body}) . "\n";
    }
    
    foreach my $child ($cb->children) {
        next unless $self->has_view($child, $view);
        $self->add_generic($child, $depth + 1, $textref);
    }
}

sub add_generic_nobullets {
    my ($self, $cb, $depth, $textref) = @_;
    
    # unpack these lil tidbits ;)
    my $lang = $self->lang;
    my $view = $self->view;
    
    my $vi = $cb->visible_item($lang);
    if ($vi) {
        my $body = $vi->body;
        $$textref .= wrap("  " x $depth, '', $body) . "\n";
    } else {
        $$textref .= wrap("  " x $depth, '', $self->empty_labels($lang)->{body}) . "\n";
    }
    
    foreach my $child ($cb->children) {
        next unless $self->has_view($child, $view);
        $self->add_generic_nobullets($child, $depth + 1, $textref);
    }
}

sub serialize_text_in {
    my ($self, $text, $format) = @_;
    my $uuid = $self->new_uuid;
    open(FILE_A, '>', "/tmp/$uuid.txt");
    print FILE_A $text;
    close(FILE_A);
    
    # do the conversion (have to use a python script (which uses soffice) fo now...)
    system("/usr/local/praux/bin/document_converter.py /tmp/$uuid.txt /tmp/$uuid.$format");
    
    if (-e "/tmp/$uuid.$format") {
        open(FILE_B, '<', "/tmp/$uuid.$format");
        my $data;
        {
            local $/;
            $data = <FILE_B>;
        }
        close(FILE_B);
        system("rm /tmp/$uuid.txt /tmp/$uuid.$format");
        return $data;
    } else {
        die "Converter didn't convert!  Sorry ;(\n"
    }
}

# sts has to work both in request context & offline
sub sts {
    my ($self, $resume, $lang, $view) = @_;
    
    # get the resume..
    unless (ref($resume) eq "Praux::DB::Resume") {
        if ($resume =~ /^\d+$/) {
            $resume = $self->resume_by_id($resume);
        } else {
            die "No valid resume specified in [S]erialize [T]okenize [S]tem algorithm.\n";
        }
    }
    
    # derive language context
    my $lang;
    if ($self->{lang}) {
        $lang = $self->{lang} unless $lang;
    } else {
        $lang = $resume->default_language unless $lang;
    }
    
    # (re)set language in the praux object.  compatible with request context & offline
    $self->{lang} = $lang;
    
    # instantiate proper stemmer.
    my $stemmer = Lingua::Stem::Snowball->new(
        lang => $lang,
        encoding => 'UTF-8',
    );
    
    # derive view context
    my $view;
    if ($self->{view}) {
        $view = $self->{view} unless $view;
    } else {
        $view = "default" unless $view;
    }

    # (re)set view in the praux object.  compatible with request context & offline
    $self->{view} = $view;
    
    # data structures for work...
    my (%unstemmed, %dont_stem, %final);

    # get all the visible items..
    my $content_items = $resume->content_items->search(
        {
            language => $lang,
            visible => 1,
        }
    );

    foreach my $vi ($content_items->all) {
        # skip section headers..
        next if $vi->content_block->format eq "section_header";


        # don't try and tokenize BBCode
        if ($vi->body && $vi->body !~ /\[\//) {
            # tokenize body by spaces..
            foreach my $word (split(/\s+/, $vi->body)) {
                $word =~ s/[\[\]\:\;]+//g;

                if (exists($stop_hash{lc($word)})) {
                    next;
                } elsif ($word !~ /[A-Za-z]+/o) {
                    next;
                } elsif ($word =~ /[\,\.]+$/o) {
                    next;
                } elsif ($word =~ /^\(/o) {
                    next;
                } elsif ($word =~ /\)$/o) {
                    next;
                }

                $unstemmed{lc($word)}++;
            }
        }

        # these should be most valuable as phrases!
        foreach my $method (qw/organization role instructor title/) {
            my $val = $vi->$method;
            $final{lc($val)}++ if $val;
        }
    }
    
    # stem (canceled for now)
    #print "[info] stemming words in $lang...\n";
    # foreach my $root_word (keys %unstemmed) {
    #     my $is_stemmed = 0;
    #     my $stem = $stemmer->stem($root_word, \$is_stemmed);
    #     if ($is_stemmed) {
    #         $final{$stem} += $unstemmed{$root_word};
    #     } else {
    #         $final{$root_word} += $unstemmed{$root_word};
    #     }
    # }

    foreach my $root_word (keys %unstemmed) {
        $final{$root_word} += $unstemmed{$root_word};
    }

    my (@all, @high, @low, $max, $thresh);
    foreach my $key (sort {$final{$b} <=> $final{$a}} keys %final) {
        # the first one in this is the biggest..
        $max = $final{$key} unless $max;

        # squash this down..
        $max = 15 if $max > 15;

        # find the threshold.
        unless ($thresh) {
            $candidate = int($max / 2);
            if ($candidate > 1) {
                $thresh = $candidate;
            } else {
                $thresh = $max;
            }
        }

        $key =~ s/^\s*(.+?)\s*/$1/g;
        push(@all, $key);
        if ($final{$key} >= $thresh) {
            # they're all junk words.. only take 15.. dont clutter.
            if (scalar(@high) < 15) {
                push(@high, $key);
            }
        } else {
            if (scalar(@high) < 10) {
                push (@high, $key);
            } else {
                push(@low, $key);
            }
        }
    }
    
    return (\@high, \@low, \@all);
}

# convenient AINT IT?!
sub similar_resumes {
    my ($self, $resume, $count) = @_;

    # make sure we get a resume ;)
    $resume = $self->resume unless $resume;
    $resume = $self->resume_by_id unless ref($resume);
    return undef unless $resume;
    
    # I don't think 'view' is actually implemented.. lol?
    my ($high, $low, $all) = $self->sts($resume, $resume->default_language, 'all');
    my @resumes = $self->full_text_search(join(', ', @$high));
    
    my (@return);
    foreach my $res (@resumes) {
        next if $res->id == $resume->id;
        push(@return, $res);
        last if scalar(@return) == $count;
    }
    
    return (@return);
}

# search through the db
sub full_text_search {
    my ($self, $query) = @_;
    my $results = $spx->Query($query, $self->c->SPHINX_IDX);
    
    my @resumes;
    foreach my $match (@{$results->{matches}}) {
        push (@resumes, $self->resume_by_id($match->{doc}));
    }
    return (@resumes);
}

# yeah.. we're finally doing facebook.
sub fb {
    my ($self) = @_;
    
    return undef unless $self->romeo;
    
    my $cookies = Apache2::Cookie->fetch($self->romeo->r);

    my $session_key = $cookies->{$self->c->FB_API_KEY . "_session_key"} ? $cookies->{$self->c->FB_API_KEY . "_session_key"}->value : undef;
    my $session_uid = $cookies->{$self->c->FB_API_KEY . "_user"} ? $cookies->{$self->c->FB_API_KEY . "_user"}->value : undef;
    my $session_expires = $cookies->{$self->c->FB_API_KEY . "_expires"} ? $cookies->{$self->c->FB_API_KEY . "_expires"}->value : undef;
    
    return WWW::Facebook::API->new(
        parse => 1,
        format => 'JSON',
        secret => $self->c->FB_APP_SECRET,
        api_key => $self->c->FB_API_KEY,
        api_version => '1.0',
        session_key => $session_key,
        session_uid => $session_uid,
        session_expires => $session_expires,
    );
}

sub user_by_external_id {
    my ($self, $uid, $type) = @_;
    return $self->schema->resultset('User')->find(
        {
            external_id => $id,
            external_type => $type,
        }
    );
}

sub fb_locale {
    my ($self) = @_;
    my $fb = $self->fb;
    my $uid = $fb->users->get_logged_in_user;
    $info = $fb->users->get_info(
        uids => [$uid],
        fields => qw/locale/,
    );
    if (ref($info) eq "ARRAY") {
        my $locale = $info->[0]->{locale};
        my ($ll, $cc) = split(/_/, $locale);
        return ($ll, $cc);
    } else {
        return undef;
    }
}

sub fb_email {
    my ($self) = @_;
    my $fb = $self->fb;
    return undef unless $fb;
    my $uid = $fb->users->get_logged_in_user;
    $info = $fb->users->get_info(
        uids => [$uid],
        fields => qw/email/,
    );
    if (ref($info) eq "ARRAY") {
        my $email = $info->[0]->{email};
        if ($email =~ /facebook/) {
            return undef;
        } else {
            return $email;
        }
    } else {
        return undef;
    }
}

sub linkup_jobs {
    my ($self, $resume) = @_;
    
    $resume = $self->resume unless $resume;
    die "No resume to be found!" unless $resume;
    
    my $cache_key = 'LinkUp' . md5_hex($resume->tokens);
    my $hr;
    
    unless ($hr = $self->memd->get($cache_key)) {
        my $ua = new LWP::UserAgent;
        $ua->agent('Praux Resumes v' . $VERSION);

        my $resp = $ua->post("http://www.linkup.com/developers/v-1/search-handler.js", {
            keyword => join(' ', split(',', $resume->tokens)), 
            method => 'any',
            orig_ip => $self->session->ip_address,
            api_key => $self->c->LINKUP_API_KEY,
            embedded_search_key => $self->c->LINKUP_EMBEDDED_SEARCH_KEY,
            per_page => 5,
            sort => 'd',
        });

        if ($resp->is_success) {
            use JSON;
            my $json = JSON->new;
            $hr = $json->decode($resp->decoded_content);
            $self->memd->set($cache_key, $hr, 3600 * 4);
        } else {
            die $resp->status_line;
        }
    }
    
    return $hr->{jobs} if ref $hr;
}

sub remote_rss_feed {
    my ($self, $feed) = @_;
    
    my $cache_key = 'RSS' . md5_hex($feed);
    my $hr;
    
    unless ($hr = $self->memd->get($cache_key)) {
        my $ua = new LWP::UserAgent;
        $ua->agent('Praux Resumes v' . $VERSION);

        my $resp = $ua->get($feed);

        if ($resp->is_success) {
            $hr = XMLin($resp->decoded_content)->{channel};
            $self->memd->set($cache_key, $hr, 28800);
        } else {
            die $resp->status_line;
        }
    }
    
    return $hr;
}

sub lang {
    my ($self) = @_;
    return $self->{lang};
}

sub view {
    my ($self) = @_;
    return $self->{view};
}

sub resume_info {
    my ($self, $resume) = @_;
    $resume = $self->resume unless ref($resume);
    
    return {} unless $resume;
    
    # get the views
    my $vh = {};
    foreach my $view ($resume->views) {
        $vh->{$view->view_name}++;
    }
    
    # get the languages
    my $lh = {};
    foreach my $ci ($resume->content_items) {
        $lh->{$ci->language}++;
    }
    
    # the available views, sorted alphabetically
    my @views = sort { $a cmp $b } keys %$vh;
    
    # the available languages, sorted alphabetically
    my @langs = sort { $a cmp $b } keys %$lh;
    
    my $ri = {
        resume => $resume->instance . $self->c->COOKIE_DOMAIN,
        hit_count => $resume->hit_count,
        name => $resume->name,
        summary => $resume->summary,
        last_change => scalar(localtime($resume->modify_time)),
        last_change_epoch => $resume->modify_time,
        owner => $resume->praux_user->id,
        completeness => $resume->completeness,
        qrcode_url => $resume->url . "/qrc/qr.png",
        default_language => $resume->default_language,
        default_theme => $resume->default_theme,
        recent_title => $resume->recent_title,
        derivative_suggestions => $resume->suggestions( derivative => 1 )->count,
        verbatim_suggestions => $resume->suggestions( verbatim => 1 )->count,
        score => $resume->votes->get_column('vote')->sum,
        views => \@views,
        languages => \@langs,
    };
    
    return $ri;
}

1;
