package Praux::DB::HitLog;

use YAML::Syck;
use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_hitlog');

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
    source_ip => {
        data_type => 'varchar',
        size => 16,
    },
    visit_hit_number => {
        data_type => 'integer',
        is_numeric => 1,
    },
    instance => {
        data_type => 'varchar',
        size => 255,
    },
    theme => {
        data_type => 'varchar',
        size => 255,
    },
    user_agent => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    referrer => {
        data_type => text,
        is_nullable => 1,
    },
    is_robot => {
        data_type => 'integer',
        is_numeric => 1,
    },
    language => {
        data_type => 'varchar',
        size => 32,
    },
    meta => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    view => {
        data_type => 'varchar',
        size => 255,
    },
    content_type => {
        data_type => 'varchar',
        size => 255,
    },
    time_taken => {
        data_type => 'real',
    },
    from_cache => {
        data_type => 'integer',
        is_numeric => 1,
    },
    create_time => {
        data_type => 'integer',
    },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(resume => 'Praux::DB::Resume', undef, { cascade_delete => 0, is_foreign_key_constraint => 0 });

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
        name => 'language_idx',
        fields => ['language'],
    );
    
    $sqlt_table->add_index(
        name => 'theme_idx',
        fields => ['theme'],
    );
    
    $sqlt_table->add_index(
        name => 'resume_idx',
        fields => ['resume'],
    );
    
    $sqlt_table->add_index(
        name => 'view_idx',
        fields => ['view'],
    );
}

1;
