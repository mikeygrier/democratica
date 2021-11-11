package Praux::DB::User::Account::Payment;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_user_account_payment');

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
    account => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
    current => {
        data_type => 'boolean',
        default_value => 0,
    },
    transaction_id => {
        data_type => 'varchar',
        size => 128,
    },
    external_transaction_id => {
        data_type => 'varchar',
        size => 255,
    },
    amount => {
        data_type => 'varchar',
        size => 64,
    },
    payment_type => {
        data_type => 'varchar',
        size => 128,
        default_value => 'paypal',
    },
    payment_time => {
        data_type => 'integer',
        is_numeric => 1,
    },
    payment_note => {
        data_type => 'varchar',
        size => 128,
    },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(owner => 'Praux::DB::User');
__PACKAGE__->belongs_to(account => 'Praux::DB::User::Account');

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
