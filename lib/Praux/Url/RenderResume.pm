# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::RenderResume;

use base qw/Praux::Url::Component/;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;

sub handle_request {
    my ($self, $romeo, @uri) = @_;
	
	# unpack the URI..
	my ($class, $function, @uri) = @uri;
	
	unless ($self->instance) {
	    ($function, @uri) = @uri;
	}
	
	my $resume = $self->resume;
    unless ($resume) {
        $romeo->r->content_type('text/html');
        $self->render_error("404: Resume not found!");
        return OK;
    }
	
	# Determine Renderer Version User-Preference
	if (my $renderer_version = $resume->praux_user->preference('com.praux.renderer.version')) {
	    $self->romeo->param('renderer_version', $renderer_version);
	}
	
	# clear the cache if the user wants us to.
	if ($self->romeo->param('clear_cache') == 1) {
	    $self->clear_all_cache();
	}
	
	# make sure this gets set here..
	$romeo->param('language_context', ($resume->default_language or 'en'));
	
	if ($function eq "praux_theme") {
        $self->{theme} = $uri[0];

        # get rid of this stuff so the rest "just works".
        ($function, @uri) = @uri[1..$#uri];
    }
    
    # / = default
    # /view/lang/ = able to do this
    # /view/ = able to do this too
    # /view/lang/.suggestions_for/48-body/ = /view/lang/
    # /.suggestions_for/48-body/ = default
    # /view
    
    # /resume/ is the same as /, always.
    if ($function eq "resume") {
        $function = undef;
    }
    
    # clear words on every request.. for some reason the praux object is persisting.. im going to assume i did that on purpose
    $self->{resume_words} = '';
    
    # new url structure
    if ($function) {
        if ($function =~ /^\./) {
            $self->{view} = 'default';
            $self->{lang} = $resume->default_language;
            $self->{resume_format} = 'xhtml';
        } elsif ($function =~ /([\w\-]+)\.(html|xhtml|pdf|doc|yaml|yml|xml|json|txt|doc|odt|rtf)$/io) {
            $self->{view} = 'default';
            $self->{lang} = $resume->default_language;
            $self->{resume_format} = $2 eq "html" ? "xhtml" : $2;
            $self->{resume_words} = $1;
        } else {
            my $next = shift(@uri);
            if ($next =~ /^\./) {
                $self->{view} = $function;
                $self->{lang} = $resume->default_language;
                $self->{resume_format} = 'xhtml';
            } else {
                if ($next =~ /([\w\-]+)\.(xhtml|html|pdf|doc|yaml|yml|xml|json|txt|doc|odt|rtf)$/io) {
                    $self->{lang} = $resume->default_language;
                    $self->{resume_format} = $2 eq "html" ? "xhtml" : $2;
                    $self->{resume_words} = $1;
                } else {
                    $self->{view} = $function;
                    my $final = shift(@uri);
                    if ($final =~ /([\w\-]+)\.(xhtml|html|pdf|doc|yaml|yml|xml|json|txt|doc|odt|rtf)$/io) {
                        $self->{lang} = $next;
                        $self->{resume_format} = $2 eq "html" ? "xhtml" : $2;
                        $self->{resume_words} = $1;
                    } else {
                        $self->{lang} = $next || $resume->default_language;
                        $self->{resume_format} = 'xhtml';
                    }
                }
            }
        }
    } else {
        $self->{view} = 'default';
        $self->{lang} = $resume->default_language;
        $self->{resume_format} = 'xhtml';
    }
    
    # ok, here we branch for displaying "unpublished"..
    unless ($self->active_user && ($self->active_user->id == $resume->praux_user->id)) {
        my $owner = $resume->praux_user;
        unless ($owner->preference('com.praux.publish_resume')) {
            $self->romeo->r->content_type('text/html;charset=utf-8');
            $self->romeo->render_page('unpublished', { self => $self });
            return OK;
        }
    }
    
    if ($self->resume_format eq "xhtml") {
        $self->romeo->r->content_type('text/html;charset=utf-8;charset=utf-8');
    } else {
        if ($self->resume_format eq "pdf") {
            $self->romeo->r->content_type('application/pdf');
        } elsif ($self->resume_format eq "yaml" || $self->resume_format eq "yml") {
            $self->romeo->r->content_type('text/x-yaml');
        } elsif ($self->resume_format eq "xml") {
            $self->romeo->r->content_type('text/xml');
        } elsif ($self->resume_format eq "txt") {
            $self->romeo->r->content_type('text/plain');
        } elsif ($self->resume_format eq "odt") {
            $self->romeo->r->content_type('application/vnd.oasis.opendocument.text');
        } elsif ($self->resume_format eq "doc") {
            $self->romeo->r->content_type('application/msword');
        } elsif ($self->resume_format eq "rtf") {
            $self->romeo->r->content_type('application/rtf');
        } elsif ($self->resume_format eq "json") {
            $self->romeo->r->content_type('application-x/javascript');
        }
    }
        
    # purge our cache so we render the login errors properly, we should move to json
    # logins for the prauxtron ok.
    if ($romeo->session->login_error) {
        # delete this cache, and dont cache this response.
        $self->clear_all_cache();
        # Version 2 Renderer
        if ($self->romeo->param('renderer_version') eq "2") {
            $self->romeo->render_page('prauxtron2',
                {
                    self => $self,
                    resume => $resume,
                    ri => $self->resume_info($resume),
                }
            );
            return OK;
        }
        
        $self->romeo->render_page('prauxtron',
            {
                self => $self,
                resume => $resume,
                ri => $self->resume_info($resume),
            }
        );
        return OK;
    }
    
    my $rendered;
    my $from_cache = 1;
    # here's where we cache / retrieve
    unless ($rendered = $self->this_cached) {
        if ($self->resume_format eq "xhtml") {
            if ($self->romeo->param('renderer_version') eq "2") {
                $rendered = $self->romeo->rendered_page('prauxtron2',
                    {
                        self => $self,
                        resume => $resume,
                        ri => $self->resume_info($resume),
                    }
                );
            } else {
                $rendered = $self->romeo->rendered_page('prauxtron',
                    {
                        self => $self,
                        resume => $resume,
                        ri => $self->resume_info($resume),
                    }
                );
            }
        } else {
            if ($self->resume_format eq "pdf") {
                my $pdf_url;
                if ($romeo->r->unparsed_uri =~ /^(?:\/rr\/|\/resume\/)/) {
                    $pdf_url = $self->root_url . "/rr/" . $resume->instance . "/";
                } else {
                    $pdf_url = "http://" . $self->instance . $self->cookie_domain . '/';
                }
                
                if ($self->theme) {
                    $pdf_url .= "/praux_theme/" . $self->theme . "/";
                }
                $pdf_url .= $self->view . "/" . $self->lang . "/";
            
                my ($left, $right) = split(/\?/, $romeo->r->unparsed_uri);
                if ($right) {
                    $pdf_url .= "?" . $right;
                }
            
                open(WKHTML2PDF, '-|', '/usr/local/bin/wkhtmltopdf -nq "' . $pdf_url . '" -');
                {
                    local $/;
                    $rendered = <WKHTML2PDF>;
                }
                close(WKHTML2PDF);
            } elsif ($self->resume_format eq "yaml" || $self->resume_format eq "yml") {
                $rendered = $resume->serialize_yaml;
            } elsif ($self->resume_format eq "xml") {
                $rendered = $resume->serialize_xml;
            } elsif ($self->resume_format eq "json") {
                $rendered = $resume->serialize_json;
            } elsif ($self->resume_format eq "txt") {
                $rendered = $self->serialize_text($resume, $self->view, $self->lang);
            } else {
                $rendered = $self->serialize_text_in($self->serialize_text($resume, $self->view, $self->lang), $self->resume_format);
            }
        }
    
        # cache!
        $self->cache_this($rendered);
        $from_cache = 0;
    }
    
    if (!$self->is_myself) {
        $resume->hit_count($resume->hit_count + 1);
        $resume->update;

        $referrer = $self->romeo->r->headers_in->get('Referer') ? $self->romeo->r->headers_in->get('Referer') : $self->romeo->r->headers_in->get('Referrer');
        
        # we're going to deprecate the hitcount soon.
        $resume->hits->create(
            {
                source_ip => $romeo->r->connection->remote_ip,
                visit_hit_number => $romeo->session->page_count ? $romeo->session->page_count : 0,
                instance => $resume->instance,
                theme => $self->theme ? $self->theme : "default",
                user_agent => $romeo->user_agent,
                is_robot => $romeo->agent_is_robot ? 1 : 0,
                language => $self->lang,
                referrer => $referrer,
                view => $self->view ? $self->view : "default",
                time_taken => $romeo->time_taken,
                content_type => $romeo->r->content_type,
                from_cache => $from_cache,
            }
        );
    }
    
    print $rendered;
    return OK;
}

sub current_theme {
    my ($self) = @_;
    if ($self->theme) {
        return $self->theme;
    } elsif ($self->view_obj && $self->view_obj->default_theme->id > 0) {
        return $self->view_obj->default_theme->theme_name;
    } elsif ($self->resume->default_theme_object && $self->resume->default_theme_object->id > 0) {
        return $self->resume->default_theme_object->theme_name;
    }
    return undef;
}

sub cache_key {
    my ($self) = @_;
    
    my $cache_key = $self->resume->instance . "/" . join('/', $self->view, $self->lang);
    
    if ($self->resume_format eq "pdf") {
        $cache_key .= "/__PDF__/";
    } elsif ($self->resume_format eq "yaml" || $self->resume_format eq "yml") {
        $cache_key .= "/__YAML__/";
    } elsif ($self->resume_format eq "xml") {
        $cache_key .= "/__XML__/";
    } elsif ($self->resume_format eq "txt") {
        $cache_key .= "/__TXT__/";
    } elsif ($self->resume_format eq "doc") {
        $cache_key .= "/__DOC__/";
    } elsif ($self->resume_format eq "odt") {
        $cache_key .= "/__ODT__/";
    } elsif ($self->resume_format eq "rtf") {
        $cache_key .= "/__RTF__/";
    } elsif ($self->resume_format eq "json") {
        $cache_key .= "/__JSON__/";
    } elsif ($self->is_myself) {
        $cache_key .= "/__MYSELF__/";
    } else {    
        if ($self->active_user) {
            $cache_key .= "/__LOGGED_IN__/";
            if ($self->active_user->id == $self->resume->praux_user->id) {
                $cache_key .= "__MINE__/";
            } else {
                $cache_key .= "__" . $self->active_user->id . "__/";
            }
        }
    }
    
    # remember + cache themed resumes!
    if ($self->theme) {
        $cache_key .= "__THEME__/" . $self->theme . "/";
    }
    
    # remember resume words!!
    if ($self->{resume_words}) {
        $cache_key .= join("_", split(/-/, $self->{resume_words})) . "/";
    }
    
    my ($left, $right) = split(/\?/, $self->romeo->r->unparsed_uri);
    if ($right) {
        $right =~ s/\&\=/_/g;
        $cache_key .= "/ARGS/" . $right . "/";
    }
    
    return $cache_key;
}

sub this_cached {
    my ($self) = @_;
    return $self->get_cache->{$self->cache_key};
}

sub cache_this {
    my ($self, $to_cache) = @_;
    my $cache = $self->get_cache;
    $cache->{$self->cache_key} = $to_cache;
    $self->set_cache($cache);
}

sub theme {
    my ($self, $theme) = @_;
    if ($theme) {
        $self->{theme} = $theme;
    }
    return $self->{theme};
}

sub lang {
    my ($self) = @_;
    return $self->{lang};
}

sub resume_words {
    my ($self) = @_;
    return join(" ", map { ucfirst($_) } split(/-/, $self->{resume_words}));
}

sub resume_format {
    my ($self) = @_;
    return $self->{resume_format};
}

sub view_obj {
    my ($self) = @_;
    return $self->resume->views->search(view_name => $self->view)->first;
}

sub view {
    my ($self) = @_;
    return $self->{view};
}

sub delete_this {
    my ($self, $all) = @_;
    
    my $cache = $self->get_cache;
    
    if ($all) {
        my $cache_key = join('/', $self->view, $self->lang);
        delete $cache->{$cache_key};
        delete $cache->{$cache_key . "/__PDF__/"};
        delete $cache->{$cache_key . "/__YAML__/"};
        delete $cache->{$cache_key . "/__JSON__/"};
        delete $cache->{$cache_key . "/__XML__/"};
        delete $cache->{$cache_key . "/__TXT__/"};
        delete $cache->{$cache_key . "/__DOC__/"};
        delete $cache->{$cache_key . "/__ODT__/"};
        delete $cache->{$cache_key . "/__RTF__/"};
        delete $cache->{$cache_key . "/__LOGGED_IN__/"};
        delete $cache->{$cache_key . "/__LOGGED_IN__/__MINE__/"};
    } else {
        delete $cache->{$self->cache_key};
    }
    
    $self->set_cache($cache);
}

1;
