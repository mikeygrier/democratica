package WWW::Romeo::DB::Session;

our @ISA = qw/DBIx::Class WWW::Romeo/;
use DBIx::Class;
use WWW::Romeo;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('session');
__PACKAGE__->add_columns(
    id                  =>      {
        is_auto_increment       =>      1,
        data_type               =>      'integer',
    },
    session_id          =>      {
        size                    =>      128,
        data_type               =>      'varchar',
    },
    expire_timestamp    =>      {
        data_type               =>      'integer',
    },
    user                =>      {
        data_type               =>      'integer',
        is_foreign_key          =>      1,
    },
    type                =>      {
        data_type               =>      'varchar',
        size => 64,
        default_value           =>      'WWW::Romeo',
    },
    external_user       =>      {
        data_type               =>      'varchar',
        is_nullable             =>      1,
        size => 255,
    },
    anonymous           =>      {
        data_type               =>      'integer',
        size                    =>      1
    },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->has_many(attributes            =>          'WWW::Romeo::DB::Session::Attribute');
__PACKAGE__->might_have(user                =>          'WWW::Romeo::DB::User');

# do this extra stuff on insert
sub insert {
    my ($self, @args) = @_;
    $self->expire_timestamp(time + $self->c->COOKIE_DURATION);

    # remove expired sessions every time we create a new session.
    $self->remove_expired;

    $self->next::method(@args);
}

# do this extra stuff on update
sub update {
    my ($self, @args) = @_;
    $self->expire_timestamp(time + $self->c->COOKIE_DURATION);
    $self->next::method(@args);
}

sub expired {
    my ($self) = @_;
    if ($self->expire_timestamp < time) {
        return 1;
    }
    return undef;
}

sub remove_expired {
    my ($self) = @_;
    $self->db->resultset('Session')->search(
        {
            expire_timestamp        =>      { '<', time },
        }
    )->delete_all;
}

1;
