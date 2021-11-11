# package to facilitate a many to many relationship between resumes and categories...
package Praux::DB::Resume::ResumeCategory;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_resume_resumecategory');

__PACKAGE__->add_columns(
    id => {
        data_type => 'integer',
        is_numeric => 1,
    },
    resume => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    category => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->belongs_to(resume => 'Praux::DB::Resume');
__PACKAGE__->belongs_to(category => 'Praux::DB::Resume::Category');

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
}

1;
