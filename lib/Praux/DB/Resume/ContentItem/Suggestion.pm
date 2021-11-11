package Praux::DB::Resume::ContentItem::Suggestion;

use YAML::Syck;
use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_resume_content_item_suggestion');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    content_item => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
    submitter => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
    resume => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
    used => {
        data_type => 'boolean',
        default_value => '0',
    },
    suggested_attribute => {
        data_type => 'varchar',
        size => 128,
    },
    suggested_value => {
        data_type => 'text',
    },
    used_time => {
        data_type => 'integer',
        is_numeric => 1,
    },
    create_time => {
        data_type => 'integer',
        is_numeric => 1,
    },
    
    # these define HOW it's used.. did we derive our own thing or did we copy it verbatim?
    derivative => {
        data_type => 'boolean',
        default_value => '0',
    },
    verbatim => {
        data_type => 'boolean',
        default_value => '0',
    },
);

__PACKAGE__->set_primary_key('id');

# please do the right thing.
__PACKAGE__->belongs_to(content_item => 'Praux::DB::Resume::ContentItem', { 'foreign.id' => 'self.content_item' }, { 
    cascade_delete => 0, 
    cascade_copy => 0, 
    is_foreign_key_constraint => 0,
});                                                                         
__PACKAGE__->has_many(changes => 'Praux::DB::Log', 'suggestion', { cascade_delete => 0 });
__PACKAGE__->belongs_to(resume => 'Praux::DB::Resume', undef, { cascade_delete => 0, is_foreign_key_constraint => 0 });
__PACKAGE__->belongs_to(submitter => 'Praux::DB::User');

sub current_value {
    my ($self) = @_;
    my $sa = $self->suggested_attribute;
    my $ci = $self->content_item;
    return $ci->$sa;
}

sub html_id {
    my ($self) = @_;
    return $self->content_item->content_block->id . "-" . $self->suggested_attribute;
}

sub insert {
    my ($self, @args) = @_;
    $self->create_time(time);
    $self->next::method(@args);
}

sub update {
    my ($self, @args) = @_;
    # keep track of the day it was used.
    if ($self->used && !$self->used_time) {
        $self->used_time(time);
    }
    $self->next::method(@args);
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
    
    $sqlt_table->add_index(
        name => 'suggested_attribute_idx',
        fields => ['suggested_attribute'],
    );

    $sqlt_table->add_index(
        name => 'create_time_idx',
        fields => ['create_time'],
    );

    $sqlt_table->add_index(
        name => 'used_time_idx',
        fields => ['create_time'],
    );

    $sqlt_table->add_index(
        name => 'used',
        fields => ['used'],
    );
    
    $sqlt_table->add_index(
        name => 'derivative_idx',
        fields => ['derivative'],
    );
    
    $sqlt_table->add_index(
        name => 'verbatim_idx',
        fields => ['verbatim'],
    );
}

1;
