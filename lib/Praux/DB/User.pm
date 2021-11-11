package Praux::DB::User;

use base qw/DBIx::Class Praux/;
use Digest::MD5 qw/md5_hex/;
use Carp qw(croak);

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_user');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    provisioner => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
    email => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    common_name => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    password => {
        data_type => 'varchar',
        size => 64,
        is_nullable => 1,
    },
    verify_token => {
        data_type => 'varchar',
        size => 64,
        is_nullable => 1,
    },
    referrer => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
        is_nullable => 1,
    },
    verified => {
        data_type => 'boolean',
        default_value => 0,
    },
    modify_time => {
        data_type => 'integer',
        is_numeric => 1,
    },
    external_id => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    external_type => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    sponsor => {
        data_type => 'integer',
        is_foreign_key => 1,
    },
    message_to_sponsor => {
        data_type => 'text',
    },
    sponsor_approved => {
        data_type => 'integer',
        default_value => 0,
    },
    gravatar_url => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    create_time => {
        data_type => 'integer',
        is_numeric => 1,
    },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->might_have(resume => 'Praux::DB::Resume', 'praux_user');
__PACKAGE__->has_many(clipboards => 'Praux::DB::User::Clipboard', 'owner');
__PACKAGE__->has_many(prefs => 'Praux::DB::User::Preferences', 'owner');
__PACKAGE__->has_many(comments => 'Praux::DB::Resume::ContentItem::Comment', 'owner');
__PACKAGE__->has_many(votes => 'Praux::DB::User::Vote', 'owner');
__PACKAGE__->might_have(account => 'Praux::DB::User::Account');
__PACKAGE__->has_many(payments => 'Praux::DB::User::Account::Payment', 'owner');
__PACKAGE__->has_many(suggestions => 'Praux::DB::Resume::ContentItem::Suggestion', 'submitter');
__PACKAGE__->has_many(delegate_relationships => 'Praux::DB::Resume::Delegate', 'delegate');
__PACKAGE__->belongs_to(provisioner => 'Praux::DB::Provisioner', undef, { cascade_delete => 0, is_foreign_key_constraint => 0 });
__PACKAGE__->has_many(actions => 'Praux::DB::Log', 'acting_user', { cascade_delete => 0});
__PACKAGE__->might_have(referrer => 'Praux::DB::User');
__PACKAGE__->might_have(sponsor => 'Praux::DB::User');
__PACKAGE__->has_many(referees => 'Praux::DB::User', 'referrer');
__PACKAGE__->has_many(endorsed => 'Praux::DB::User', 'sponsor');

sub gravatar {
    my ($self) = @_;
    return Praux::gravatar($self->email);
}

sub recent_suggestions_paged {
    my ($self, $page) = @_;
    return $self->actions->search_rs({action => 'Praux::Url::JSON::AddSuggestion'},
        {
            order_by => 'create_time DESC',
            rows => 15,
            page => $page ? $page : 1,
        }
    );
}

sub recent_suggestions {
    my ($self, $page) = @_;
    return $self->actions->search_rs({action => 'Praux::Url::JSON::AddSuggestion'},
        {
            order_by => 'create_time DESC',
        }
    );
}

sub first_name {
    my ($self) = @_;
    return (split(/\s+/, $self->common_name))[0];
}

sub suggested_resume_host {
    my ($self) = @_;
    my $suggested_instance = join('.', split(/\s+/, lc($self->common_name)));
    my $i = 2;
    
    # no concurrent periods..
    $suggested_instance =~ s/\.{2,}/\./g;
    
    # no periods at the end!
    $suggested_instance =~ s/\.$//g;
    
    # increment if need-be
    my $oi = $suggested_instance;
    while ($self->resume_by_instance($suggested_instance)) {
        $suggested_instance = $oi . $i;
        $i++;
    }
    
    return $suggested_instance . $self->c->COOKIE_DOMAIN;
}

sub preference {
    my ($self, $key, $val) = @_;
    if (defined($val)) {
        return $self->set_preference($key, $val);
    } else {
        return $self->get_preference($key);
    }
}

sub set_preference {
    my ($self, $key, $val) = @_;
    if (my $pref = $self->prefs->find({ preference_name => $key })) {
        $pref->preference_value($val);
        $pref->update;
        return $pref->preference_value;
    } else {
        my $pref = $self->schema->resultset('Praux::DB::User::Preferences')->create(
            {
                preference_name => $key,
                preference_value => $val,
                owner => $self->id,
            }
        );
        return $pref->preference_value;
    }
}

sub get_preference {
    my ($self, $key) = @_;
    if (my $pref = $self->prefs->find({ preference_name => $key })) {
        return $pref->preference_value;
    }
    return undef;
}

sub insert {
    my ($self, @args) = @_;
    if ($self->is_unique) {
        $self->password(md5_hex($self->password));
        $self->create_time(time);
        $self->next::method(@args);
    }
}

sub update {
    my ($self, @args) = @_;
    # auto-encrypt the passwords on change!
    if ($self->is_column_changed('password')) {
        $self->password(md5_hex($self->password));
    }
    $self->modify_time(time);
    $self->next::method(@args);
}

sub authenticate {
    my ($self, $try) = @_;
    if ($self->password eq md5_hex($try)) {
        return 1;
    }
    return undef;
}

sub is_unique {
    my ($self) = @_;
    if ($self->user_by_email($self->email)) {
        croak("Email address " . $self->email . " is not unique!");
    }
    return 1;
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
    
    # index on email
    $sqlt_table->add_index(
        name => 'email_idx', 
        fields => ['email'],
    );
    
    # index on verify_token
    $sqlt_table->add_index(
        name => 'verify_token_idx', 
        fields => ['verify_token'],
    );
    
    # index on external_type
    $sqlt_table->add_index(
        name => 'external_type_idx', 
        fields => ['external_type'],
    );
    
    # index on external_id
    $sqlt_table->add_index(
        name => 'external_id_idx', 
        fields => ['external_id'],
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
