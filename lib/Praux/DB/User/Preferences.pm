package Praux::DB::User::Preferences;

use base qw/DBIx::Class Praux/;
use Digest::MD5 qw/md5_hex/;
use Carp qw(croak);

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_user_preferences');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    owner => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
    preference_name => {
        data_type => 'varchar',
        size => 128,
    },
    preference_value => {
        data_type => 'text',
    },
    create_time => {
        data_type => 'integer',
        is_numeric => 1,
    }
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(owner => 'Praux::DB::User');

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
}

sub insert {
    my ($self, @args) = @_;
    $self->create_time(time);
    $self->next::method(@args);
}

1;
