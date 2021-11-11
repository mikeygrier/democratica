package Praux::DB::Provisioner;

use base qw/DBIx::Class Praux/;
use Digest::MD5 qw/md5_hex/;
use Carp qw(croak);

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_provisioner');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    contact_email => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    contact_name => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    common_name => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    address => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    phone => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    kid_tested => {
        data_type => 'integer',
        default_value => 0,
    },
    mother_approved => {
        data_type => 'integer',
        default_value => 0,
    },
    num_employees => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    industry => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    provision_key => {
        data_type => 'varchar',
        size => 128,
        is_nullable => 1,
    },
    provision_hash => {
        data_type => 'varchar',
        size => 128,
        is_nullable => 1,
    },
    emblem => {
        data_type => 'blob',
        is_nullable => 1,
    },
    verify_email => {
        data_type => 'boolean',
        default_value => 1,
    },
    create_resume => {
        data_type => 'boolean',
        default_value => 0,
    },
    force_defaults => {
        data_type => 'boolean',
        default_value => 0,
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
__PACKAGE__->has_many(defaults => 'Praux::DB::Provisioner::Defaults', 'provisioner');
__PACKAGE__->has_many(users => 'Praux::DB::User', 'provisioner');

sub default {
    my ($self, $key, $val) = @_;
    if ($val) {
        return $self->set_default($key, $val);
    } else {
        return $self->get_default($key);
    }
}

sub set_default {
    my ($self, $key, $val) = @_;
    if (my $pref = $self->defaults->find({ default_name => $key })) {
        $pref->default_value($val);
        $pref->update;
        return $pref->default_value;
    } else {
        my $pref = $self->defaults->create(
            {
                default_name => $key,
                default_value => $val,
            }
        );
        return $pref->default_value;
    }
}

sub get_default {
    my ($self, $key) = @_;
    if (my $pref = $self->defaults->find({ default_name => $key })) {
        return $pref->default_value;
    }
    return undef;
}

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

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
    
    # word
    $sqlt_table->add_index(
        name => 'provision_hash_idx',
        fields => ['provision_hash'],
    );
    $sqlt_table->add_index(
        name => 'provision_key_idx',
        fields => ['provision_key'],
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