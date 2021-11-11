package Praux::DB::User::Account;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_user_account');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    owner => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    current => {
        data_type => 'boolean',
        default_value => 0,
    },
    subscription_level => {
        data_type => 'integer',
        default_value => 0,
        is_numeric => 1,
    },
    payment_type => {
        data_type => 'varchar',
        size => '128',
        default_value => 'paypal',
    },
    modify_time => {
        data_type => 'integer',
        is_numeric => 1,
    },
    create_time => {
        data_type => 'integer',
        is_numeric => 1,
    },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(owner => 'Praux::DB::User');
__PACKAGE__->has_many(payments => 'Praux::DB::User::Account::Payment');

sub insert {
    my ($self, @args) = @_;
    $self->create_time(time);
    $self->next::method(@args);
}

sub update {
    my ($self, @args) = @_;
    $self->modify_time(time);
    $self->next::method(@args);
}

# just an alias, mam
sub level {
    my ($self) = @_;
    return $self->subscription_level;
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
}

1;
