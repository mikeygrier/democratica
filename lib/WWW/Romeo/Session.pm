package WWW::Romeo::Session;

use base qw/WWW::Romeo/;
use Digest::MD5 qw/md5_hex/;

sub new {
    my ($class, %attr) = @_;

    my $self = bless(\%attr, $class);

    for (qw/anon user pass type/) {
        $self->{ucfirst($_)} = $self->{$_} if $self->{$_};
    }

    # return established sessions right off
    if (my $session_id = $self->{session_id}) {
        my $session = $self->db->resultset('Session')->search(
            {   
                session_id      =>      $session_id,
            }
        )->first;

        if (!$session || $session->expired) {
            $self->{status} = 'expired';
        } else {
            $self->{status} = 'active';
        }

        $self->{s_dbix} = $session;

        return $session ? $self : undef;
    }

    # kk -- now we make teh new sezziuns. -- get a session id
    my ($session_id, $user) = $self->new_session_id;

    my $session;     
    if ($session_id) {
        if ($user) {
            if ($self->{Type}) {
                # this is an external user.
                $session = $self->db->resultset('Session')->create(
                    {
                        session_id          =>      $session_id,
                        anonymous           =>      0, 
                        type                =>      $self->{Type},
                        external_user       =>      $user,
                    }
                );
            } else {
                $session = $self->db->resultset('Session')->create(
                    {
                        session_id          =>      $session_id,
                        user                =>      $user,
                        anonymous           =>      0,
                    }
                );
            }
            $self->{status} = 'active';
            $self->{is_new} = 1;
        } else {
            $session = $self->db->resultset('Session')->create(
                {   
                    session_id          =>      $session_id,
                    anonymous           =>      1,
                }
            );
            $self->{status} = 'active';
            $self->{is_new} = 1;
        }
    }

    $self->{s_dbix} = $session;
    return $session ? $self : undef;
}

sub new_session_id {
    my ($self) = @_;
    if ($self->{User}) {
        $user = $self->db->resultset('User')->search({username => $self->{User}})->first;
        if (!$user) {
            warn "No such user!\n" unless $quiet;
            return undef;
        }

        if ($user->authenticate($self->{Pass})) {
            # we're an authenticated session
            return (_rand_md5hex($self->{Pass}), $user);
        } else {
            # authentication failed
            warn "Invalid login and password!\n" unless $quiet;
            return undef;
        }
    } elsif ($self->{Anon}) {
        # we're an anonymous session
        return _rand_md5hex('anonymous');
    }

    #warn "Improper session credentials!\n" unless $quiet;
    return undef;
}

sub _rand_md5hex {
    my ($password) = @_;
    $password = substr($_[0], sprintf('%d', rand(length($password))), 4) if ($_[0]);
    my ($r1, $r2, $r3, $r4);
    $r1 = sprintf('%d2', rand(100));
    $r2 = rand($r1);
    $r3 = sprintf('%d2', rand(122580 + $r2));
    $r4 = rand($r3 + $r2);
    return md5_hex("$r1$r2$r3$password$r4");
}

sub status {
    my ($self) = @_;
    return $self->{status};
}

sub anonymous {
    my ($self) = @_;
    return $self->{anonymous};
}

sub is_new {
    my ($self) = @_;
    return $self->{is_new};
}

sub external_user {
    my ($self) = @_;
    return $self->{s_dbix}->external_user;
}

sub user {
    my ($self) = @_;
    #warn "User called!\n";
    if (my $uid = $self->{s_dbix}->external_user) {
        warn "You need to subclass WWW::Romeo::Session to handle your application's user instantiation.\n";
    } else {
        if ($self->{s_dbix}->anonymous) {
            return "anonymous";
        } else {
            return $self->{s_dbix}->user->username;
        }
    }
}

sub session_id {
    my ($self) = @_;
    return $self->{s_dbix}->session_id;
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

    my $attribute = $self->{s_dbix}->attributes->search(
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
            $self->{s_dbix}->attributes->create(
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
