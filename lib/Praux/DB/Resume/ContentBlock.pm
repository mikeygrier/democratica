package Praux::DB::Resume::ContentBlock;

use YAML::Syck;
use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_resume_content_block');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    resume => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
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
    section => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    parent => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(section => 'Praux::DB::Resume::Section');
__PACKAGE__->belongs_to(resume => 'Praux::DB::Resume');
__PACKAGE__->might_have(parent => 'Praux::DB::Resume::ContentBlock');
__PACKAGE__->has_many(children => 'Praux::DB::Resume::ContentBlock', 'parent');
__PACKAGE__->has_many(views => 'Praux::DB::Resume::View', 'content_block');
__PACKAGE__->has_many(content_items => 'Praux::DB::Resume::ContentItem', 'content_block');
__PACKAGE__->has_many(votes => 'Praux::DB::User::Vote', 'content_block');
__PACKAGE__->has_many(comments => 'Praux::DB::Resume::ContentItem::Comment', 'content_block');
__PACKAGE__->has_many(changes => 'Praux::DB::Log', 'content_block', { cascade_delete => 0});

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

sub serialize_yaml {
    my ($self) = @_;
    return Dump($self->to_data);
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

# this one's recursive.
# we want to pass a hash ref to populate.
sub to_data {
    my ($self, $export) = @_;
    
    my $base = 0;
    unless ($export) {
        $export = {};
        $base = 1;
    }
    
    $export->{content_items} = [];
    
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
    
    # first add our content items..
    foreach my $ci ($self->content_items) {
        push (@{$export->{content_items}}, $ci->to_data);
    }
    
    # recurse for our children.. do it for the kids.
    if ($self->children->count) {
        $export->{children} = [];
        foreach my $child ($self->children) {
            my $child_export = {};
            push(@{$export->{children}}, $child_export);
            
            # populate the child export.
            $child->to_data($child_export);
        }
    }
    
    # return only our base export since this is built by reference.
    return $export if $base;
}

sub sorted_children {
    my ($self) = @_;
    return $self->children->search({}, {order_by => ['sort_order ASC']});
}

sub visible_item {
    my ($self, $lang) = @_;
    return $self->content_items->find(
        {
            visible => 1,
            language => $lang,
        }
    );
}

sub invisible_items {
    my ($self) = @_;
    return $self->content_items->find(
        {
            visible => 0,
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
                resume => $self->section->resume->id,
                content_block => $self->id,
                view_name => $view,
                owner => $self->section->resume->praux_user->id,
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
