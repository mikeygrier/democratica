# $Id: JSON.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Tools::Hub;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux;
use Praux::Url::Component;

use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use JSON;
use XML::Simple;
use YAML::Syck;

my $json = new JSON;

my %tools_map = (
    # provisioning
    provision => 'Praux::Tools::Provision',
    prauxvision => 'Praux::Tools::Provision',
    pv => 'Praux::Tools::Provision',
    
    # content_search and shorthand
    content_search => 'Praux::Tools::ContentSearch',
    cs => 'Praux::Tools::ContentSearch',
    
    # list_resumes and shorthand
    list_resumes => 'Praux::Tools::ListResumes',
    lr => 'Praux::Tools::ListResumes',
    
    # resume_info and shorthand
    resume_info => 'Praux::Tools::ResumeInfo',
    ri => 'Praux::Tools::ResumeInfo',
    
    # create_collection and shorthand
    create_collection => 'Praux::Tools::CreateCollection',
    cc => 'Praux::Tools::CreateCollection',

    # edit_collection and shorthand
    edit_collection => 'Praux::Tools::EditCollection',
    ec => 'Praux::Tools::EditCollection',
    
    # edit_collection and shorthand
    get_collection => 'Praux::Tools::GetCollection',
    gc => 'Praux::Tools::GetCollection',
);

# these are available in XHTML!
my %template_map = (
    'Praux::Tools::ContentSearch' => 'PT_content_search.htmlt',
    'Praux::Tools::ListResumes' => 'PT_list_resumes.htmlt',
    'Praux::Tools::ResumeInfo' => 'PT_resume_info.htmlt',
);

sub handle_request {
    my ($self, $romeo, @uri) = @_;

    my ($this, $function) = (shift(@uri), shift(@uri));

    my ($function, $ext) = split(/\./, $function);

    if ($function eq "cs" && $ext eq "xhtml") {
        if ($romeo->r->args) {
            $romeo->r->headers_out->set(Location => "/page/content_search/?" . $romeo->r->args);
        } else {
            $romeo->r->headers_out->set(Location => "/page/content_search/");
        }
        return REDIRECT;
    } elsif ($function eq "lr" && $ext eq "xhtml") {
        if ($romeo->r->args) {
            $romeo->r->headers_out->set(Location => "/page/master_list/?" . $romeo->r->args);
        } else {
            $romeo->r->headers_out->set(Location => "/page/master_list/");
        }
        return REDIRECT;
    }

    my $to_serialize = {};

    if ($self->resume) {
        # can't run praux tools from inside a resume!
        $self->romeo->r->content_type('text/html');
        $self->render_error("Can't run PrauxTools from a resume URL!");
        return OK;
    }

    if (exists($tools_map{$function})) {
        $romeo->param('dispatched_from', $function);
        $to_serialize = $self->romeo->run_extension($tools_map{$function}, @uri);
    } else {
        $to_serialize = {
                success => 0,
                error => "Praux does not know about whatever it is you're trying to do. ($function)",
        };
    }
    
    # default to json!
    $ext = "json" unless $ext;
    if ($ext eq "json") {
        $self->romeo->r->content_type('application/x-javascript');
        print $json->encode($to_serialize);
    } elsif ($ext eq "yaml") {
        $self->romeo->r->content_type('text/x-yaml');
        print Dump($to_serialize);
    } elsif ($ext eq "xml") {
        $self->romeo->r->content_type('text/xml');
        print XMLout($to_serialize);
    } elsif ($ext eq "xhtml") {
        $self->romeo->r->content_type('text/html');
        $self->render_page($template_map{$tools_map{$function}}, {pt_data => $to_serialize}) or $self->render_error("Can't render page $template_map{$tools_map{$function}}: $!, $@");
    }
    
    return OK;
}

1;