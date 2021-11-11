package WWW::Romeo::DB::User;

our @ISA = qw/DBIx::Class WWW::Romeo/;
use DBIx::Class;
use WWW::Romeo;
use Digest::MD5 qw(md5_hex);

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('user');
__PACKAGE__->add_columns(
    id                  =>      {
        is_auto_increment       =>      1,
        data_type               =>      'integer',
    },
    username            =>      {
        size                    =>      80,
        data_type               =>      'varchar',
    },
    password            =>      {
        size                    =>      80,
        data_type               =>      'varchar',
    },
    common_name         =>      {
        size                    =>      128,
        data_type               =>      'varchar',
    },
    create_time         =>      {
        data_type               =>      'integer',
        is_nullable             =>      1,
    },
    modify_time         =>      {
        data_type               =>      'integer',
        is_nullable             =>      1,
    },   
    flags               =>      {
        data_type               =>      'text',
        is_nullable             =>      1,
    },
    rudiments           =>      {
        data_type               =>      'text',
        is_nullable             =>      1,
    },
    email               =>      {
        data_type               =>      'varchar',
        size                    =>      255,
        is_nullable             =>      1,
    },
);

__PACKAGE__->inflate_column('flags', {
    inflate => sub {
        return [ split(/,/, shift) ];
    },
    deflate => sub {
        my $flags = shift;
        return join(',', @$flags);
    },
});

__PACKAGE__->set_primary_key('id');
__PACKAGE__->has_many(attributes            =>          'WWW::Romeo::DB::User::Attribute');
__PACKAGE__->has_many(sessions              =>          'WWW::Romeo::DB::Session');

# do this extra stuff on insert
sub insert {
    my ($self, @args) = @_;
    $self->password(md5_hex($self->password));
    $self->create_time(time);
    $self->modify_time(time);
    $self->next::method(@args);
}

# do this extra stuff on update
sub update {
    my ($self, @args) = @_;
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

sub add_flag {
    my ($self, $flag) = @_;
    return undef unless $flag =~ /^[A-Za-z_]{1,32}$/;
    unless ($self->has_flag($flag)) {
        # add the damn flag to the data structure
        my $flags = $self->flags;
        push(@$flags, $flag);
        $self->flags($flags);
        $self->update;
    }
    return undef;
}

sub has_flag {
    my ($self, $flag) = @_;
    foreach my $fl (@{$self->flags}) {
        return 1 if $fl eq $flag;
    }
    return undef;
}

sub remove_flag {
    my ($self, $flag) = @_;
    return undef unless $flag =~ /^[A-Za-z_]{1,32}$/;
    if ($self->has_flag($flag)) {
        my $flags = $self->flags;
        my @new_flags;
        foreach my $fl (@$flags) {
            push(@new_flags, $fl) unless $fl eq $flag;
        }
        $self->flags(\@new_flags);
        $self->update;
    }
    return undef;
}

sub DESTROY {
    return;
}

# the autoloader.  is here.  scary.
sub AUTOLOAD {
    my ($self, $arg) = @_;
    our $AUTOLOAD;
    my $name = $AUTOLOAD;
    $name =~ s/.*:://g;
    my $attribute = $self->attributes->search(
        {   
            k     =>      $name,
        }
    )->first;

    if ($attribute) {
        if ($arg) {
            if ($arg eq "__clear__") {
                $attribute->delete;
            } else {
                $attribute->v($arg);
                $attribute->update;
            }
        }
        return $attribute->v();
    } else {
        if ($arg) {
            $self->attributes->create(
                {
                    k         =>      $name,
                    v         =>      $arg,
                }
            );
            return $arg;
        } else {
            return undef;
        }
    }
}

1;
