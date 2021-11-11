package Praux::DB::Resume::Section;

use YAML::Syck;
use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_resume_section');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    format => {
        data_type => 'varchar',
        is_nullable => 1,
        size => 64,
    },
    sort_order => {
        data_type => 'integer',
        is_nullable => 1,
        is_numeric => 1,
    },
    resume => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(resume => 'Praux::DB::Resume');
__PACKAGE__->has_many(views => 'Praux::DB::Resume::View', 'section');
__PACKAGE__->has_many(content_blocks => 'Praux::DB::Resume::ContentBlock');
__PACKAGE__->has_many(votes => 'Praux::DB::User::Vote', 'section');
__PACKAGE__->has_many(comments => 'Praux::DB::Resume::ContentItem::Comment', 'section');
__PACKAGE__->has_many(changes => 'Praux::DB::Log', 'section', { cascade_delete => 0});

sub insert {
    my ($self, @args) = @_;
    
    # update the resume modify time..
    my $resume = $self->resume;
    $resume->modify_time(time);
    $resume->update;
    
    $self->next::method(@args);
}

sub update {
    my ($self, @args) = @_;
    
    # update the resume modify time..
    my $resume = $self->resume;
    $resume->modify_time(time);
    $resume->update;
  
    $self->next::method(@args);
}

# returns an array ref of view names
sub view_names {
    my ($self) = @_;
    my $views = [];
    
    foreach my $view ($self->views) {
        push (@$views, $view->view_name);
    }
    
    return $views;
}

sub serialize_yaml {
    my ($self) = @_;
    return Dump($self->to_data);
}

sub to_data {
    my ($self) = @_;
    my $export = {
        content_blocks => [],
    };
    
    # only add them if they're defined.
    foreach my $method (qw/format sort_order/) {
        if (defined($self->$method)) {
            $export->{$method} = $self->$method;
        }
    }
    
    # view names <=> views
    if ($self->views) {
        $export->{views} = $self->view_names;
    }
    
    foreach my $cb ($self->content_blocks->search({ parent => 0 })) {
        push(@{$export->{content_blocks}}, $cb->to_data);
    }
    
    return $export;
}

sub sorted_content_blocks {
    my ($self) = @_;
    return $self->content_blocks->search({}, {order_by => ['sort_order ASC']});
}

sub header {
    my ($self) = @_;
    return $self->content_blocks->find(
        {
            format => 'section_header',
        }
    )->visible_item->body;
}

sub header_cb {
    my ($self) = @_;
    return $self->content_blocks->find(
        {
            format => 'section_header',
        }
    );
}

sub set_views {
    my ($self, @views) = @_;
    
    # get rid of our views..
    $self->views->delete;
    
    # add these here new ones.
    foreach my $view (@views) {
        $self->result_source->schema->resultset('Resume::View')->create(
            {
                resume => $self->resume->id,
                section => $self->id,
                view_name => $view,
                owner => $self->resume->praux_user->id,
            }
        );
    }
}

sub add_view {
    my ($self, $view) = @_;
    return undef unless $view =~ /^[A-Za-z_]{1,32}$/;
    
    my $view_obj = $self->views->find_or_create({
        view_name => lc($view),
        section => $self->id,
    });
    
    return $view_obj;
}

sub has_view {
    my ($self, $view) = @_;
    
    return $self->views->find(
        view_name => lc($view),
    );
}

sub remove_view {
    my ($self, $view) = @_;
    return undef unless $view =~ /^[A-Za-z_]{1,32}$/;
    
    my $view_obj = $self->has_view($view);
    
    if ($view_obj) {
        return $view_obj->delete;
    }
    
    return undef;
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
}

1;
