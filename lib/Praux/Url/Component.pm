package Praux::Url::Component;

use WWW::Romeo::Extension;

@ISA = qw/WWW::Romeo::Extension Praux/;

# just a handy class abstraction for Praux Url Components...

sub render_page {
    my ($self, $page, $ns) = @_;
    $page .= ".htmlt" unless $page =~ /^.+\.htmlt$/o;
    $ns->{romeo} = $self->romeo;
    $ns->{fe} = $self->romeo;
    $ns->{self} = $self;
    $ns->{vm} = $self;
    $self->romeo->template->process($self->romeo->theme . '/' . $page, $ns) or 
        $self->romeo->render_error("Couldn't process " . $self->romeo->theme . "/$page: $!, $@", $ns);
}

sub content_type {
    my ($self, $type) = @_;
    $self->romeo->r->content_type($type);
}

sub render_error {
    my ($self, $error) = @_;
    $self->romeo->render_error($error);
}

sub rendered_page {
    my ($self, $page, $ns) = @_;
    my $output;
    $page .= ".htmlt" unless $page =~ /^.+\.htmlt$/o;
    $ns->{romeo} = $self->romeo;
    $ns->{fe} = $self->romeo;
    $ns->{self} = $self;
    $ns->{vm} = $self;
    $self->romeo->template->process($self->romeo->theme . '/' . $page, $ns, \$output) or 
        $self->romeo->template->process($self->romeo->theme . '/error.htmlt', 
            { error => "Couldn't process " . $self->romeo->theme . "/$page: $!, $@" }, \$output);
            
    return $output;
}

sub render_generic_spanonly {
    my ($self, $cb) = @_;
    my $renderer_version = $self->romeo->param('renderer_version');
    my $template = "<% PROCESS praux/prauxtron$renderer_version/prauxtron_blocks.htmlt %><% INCLUDE generic %>";
    my $rendered_block;
    
    # just for our $self interest, explicity set language context for this
    $self->{lang} = $self->romeo->param('language_context');
    
    # give it away.. give it away now.
    $self->romeo->template->process(\$template, 
        {
            self => $self,
            resume => $self->resume,
            cb => $cb,
            romeo => $self->romeo,
            spanonly => 1,
        }, \$rendered_block
    ) or warn $self->romeo->template->error() . " $@ ";
    
    return $rendered_block;
}

sub render_content_block {
    my ($self, $cb) = @_;
    my $renderer_version = $self->romeo->param('renderer_version');
    my $template = "<% PROCESS praux/prauxtron$renderer_version/prauxtron_blocks.htmlt %><% INCLUDE " . $cb->format . " %>";
    my $rendered_block;
    
    # just for our $self interest, explicity set language context for this
    $self->{lang} = $self->romeo->param('language_context');
    
    # give it away.. give it away now.
    $self->romeo->template->process(\$template, 
        {
            self => $self,
            resume => $self->resume,
            cb => $cb,
            romeo => $self->romeo,
        }, \$rendered_block
    ) or warn $self->romeo->template->error() . " $@ ";
    
    return $rendered_block;
}

sub render_section {
    my ($self, $section) = @_;
    my $renderer_version = $self->romeo->param('renderer_version');
    my $template = "<% PROCESS praux/prauxtron$renderer_version/prauxtron_blocks.htmlt %><% INCLUDE section %>";
    my $rendered_section;
    
    # just for our $self interest, explicity set language context for this
    $self->{lang} = $self->romeo->param('language_context');
    
    # render a section. render two.
    $self->romeo->template->process(\$template, 
        {
            self => $self,
            resume => $self->resume,
            section => $section,
            romeo => $self->romeo,
        }, \$rendered_section
    ) or warn $self->romeo->template->error() . " $@ ";
    
    return $rendered_section;
}

1;
