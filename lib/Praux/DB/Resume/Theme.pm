package Praux::DB::Resume::Theme;

use YAML::Syck;
use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_resume_theme');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    resume => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    owner => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    deploy_type => {
        data_type => 'varchar',
        size => 128,
        is_nullable => 1,
    },
    deploy_uuid => {
        data_type => 'varchar',
        size => 128,
    },
    theme_name => {
        data_type => 'varchar',
        size => 128,
    },
    custom_sort_order => {
        data_type => 'text',
        is_nullable => 1,
    },
);

# this is how we'll handle custom serialized sort orders
__PACKAGE__->inflate_column('custom_sort_order', {
    inflate => sub {
        return [ split(/,/, shift) ];
    },
    deflate => sub {
        my $order = shift;
        return join(',', @$order);
    },
});

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(resume => 'Praux::DB::Resume');
__PACKAGE__->belongs_to(owner => 'Praux::DB::User');

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
}

1;
