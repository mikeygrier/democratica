package Praux::DB::Log;

use YAML::Syck;
use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_log');

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
    acting_user => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
    content_block => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
    content_item => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
    section => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
    suggestion => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
    instance => {
        data_type => 'varchar',
        size => 255,
    },
    action => {
        data_type => 'varchar',
        size => 255,
    },
    new_value => {
        data_type => 'text',
    },
    old_value => {
        data_type => 'text',
    },
    create_time => {
        data_type => 'integer',
    }
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(acting_user => 'Praux::DB::User', undef, { cascade_delete => 0, is_foreign_key_constraint => 0 });
__PACKAGE__->belongs_to(resume => 'Praux::DB::Resume', undef, { cascade_delete => 0, is_foreign_key_constraint => 0 });
__PACKAGE__->belongs_to(content_block => 'Praux::DB::Resume::ContentBlock', undef, { cascade_delete => 0, is_foreign_key_constraint => 0 });
__PACKAGE__->belongs_to(content_item => 'Praux::DB::Resume::ContentItem', undef, { cascade_delete => 0, is_foreign_key_constraint => 0 });
__PACKAGE__->belongs_to(section => 'Praux::DB::Resume::Section', undef, { cascade_delete => 0, is_foreign_key_constraint => 0 });
__PACKAGE__->belongs_to(suggestion => 'Praux::DB::Resume::ContentItem::Suggestion', undef, { cascade_delete => 0, is_foreign_key_constraint => 0 });

sub insert {
    my ($self, @args) = @_;
    $self->create_time(time);
    $self->next::method(@args);
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
    
    # create time
    $sqlt_table->add_index(
        name => 'create_time_idx',
        fields => ['create_time'],
    );
    
    $sqlt_table->add_index(
        name => 'instance_idx',
        fields => ['instance'],
    );
    
    $sqlt_table->add_index(
        name => 'action_idx',
        fields => ['action'],
    );
}

1;
