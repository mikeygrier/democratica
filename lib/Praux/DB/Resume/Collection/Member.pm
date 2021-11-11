package Praux::DB::Resume::Collection::Member;

use YAML::Syck;
use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_resume_collection_member');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    collection => {
        is_foreign_key => 1,
        is_numeric => 1,
        data_type => 'integer',
    },
    resume => {
        is_foreign_key => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    create_time => {
        data_type => 'integer',
    },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->belongs_to(resume => 'Praux::DB::Resume');
__PACKAGE__->belongs_to(collection => 'Praux::DB::Resume::Collection');

# make sure we keep create time up to date..
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
}

1;
