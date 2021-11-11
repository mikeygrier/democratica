package Praux::DB::Resume::ContentItem;

use YAML::Syck;
use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_resume_content_item');

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
    visible => {
        data_type => 'boolean',
        default => 0,
    },
    content_block => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    date_range => {
        data_type => 'varchar',
        size => 128,
        is_nullable => 1,
    },
    submitter => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    organization => {
        data_type => 'varchar',
        is_nullable => 1,
        size => 255,
    },
    locality => {
        data_type => 'varchar',
        is_nullable => 1,
        size => 255,
    },
    role => {
        data_type => 'varchar',
        is_nullable => 1,
        size => 255,
    },
    instructor => {
        data_type => 'varchar',
        is_nullable => 1,
        size => 255,
    },
    title => {
        data_type => 'varchar',
        is_nullable => 1,
        size => 255,
    },
    body => {
        data_type => 'text',
        is_nullable => 1,
    },
    language => {
        data_type => 'varchar',
        size => 32,
        default_value => 'en',
    },
    origin => {
        data_type => 'integer',
        is_numeric => 1,
        is_nullable => 1,
    },
    create_time => {
        data_type => 'integer',
        is_nullable => 1,
        is_numeric => 1,
    },
    modify_time => {
        data_type => 'integer',
        is_nullable => 1,
        is_numeric => 1,
    },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->might_have(origin => 'Praux::DB::Resume::ContentItem');
__PACKAGE__->belongs_to(content_block => 'Praux::DB::Resume::ContentBlock');
__PACKAGE__->belongs_to(resume => 'Praux::DB::Resume');
__PACKAGE__->has_many(votes => 'Praux::DB::User::Vote', 'content_item');
__PACKAGE__->has_many(comments => 'Praux::DB::Resume::ContentItem::Comment', 'content_item');
__PACKAGE__->has_many(suggestions => 'Praux::DB::Resume::ContentItem::Suggestion', 'content_item', { cascade_delete => 0 });
__PACKAGE__->has_many(changes => 'Praux::DB::Log', 'content_item', { cascade_delete => 0});

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

sub to_data {
    my ($self) = @_;
    my $export = {};
    foreach my $method (qw/visible date_range organization locality role instructor title body language create_time modify_time/) {
        if (defined($self->$method)) {
            $export->{$method} = $self->$method;
        }
    }
    
    if ($self->origin) {
        $export->{origin} = $self->origin->id;
    }
    
    unless (exists($export->{origin}) && $export->{origin}) {
        $export->{origin} = $self->id;
    }
    
    return $export;
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
    
    $sqlt_table->add_index(
        name => 'date_range_idx',
        fields => ['date_range'],
    );
    
    $sqlt_table->add_index(
        name => 'organization_idx',
        fields => ['organization'],
    );
    
    $sqlt_table->add_index(
        name => 'locality_idx',
        fields => ['locality'],
    );
    
    $sqlt_table->add_index(
        name => 'role_idx',
        fields => ['role'],
    );
    
    $sqlt_table->add_index(
        name => 'instructor_idx',
        fields => ['instructor'],
    );

    $sqlt_table->add_index(
        name => 'title_idx',
        fields => ['title'],
    );
    
    $sqlt_table->add_index(
        name => 'language_idx',
        fields => ['language'],
    );
    
    # modify and create times
    $sqlt_table->add_index(
        name => 'modify_time_idx',
        fields => ['modify_time'],
    );
    $sqlt_table->add_index(
        name => 'create_time_idx',
        fields => ['create_time'],
    );
}

1;
