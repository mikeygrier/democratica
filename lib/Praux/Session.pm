package Praux::Session;

#
# don't take my word on it, but i think this is finally sane
# 

use vars qw/@ISA/;

# autoloader last ;)
@ISA = qw(Praux WWW::Romeo::Session);
use Praux;
use WWW::Romeo::Session;
use Digest::MD5 qw(md5_hex);

*new = \&WWW::Romeo::Session::new;

our $quiet = 1;

sub new_session_id {
    my ($self) = @_;
    if ($self->{User}) {

        my $user = Praux::user_by_email($self, $self->{User});

        # I was doing this twice.. wtf is wrong w/ me
        unless ($user) {
            # no such user..
            # we're inheriting an autoloader, let's be explicit here
            $self->log_error("Invalid user name: $self->{User}");
            return undef;
        }

        # make it known that this is a Praux user!
        $self->{Type} = "Praux";

        if ($user->authenticate($self->{Pass})) {
            # we're an authenticated session
            return (_rand_md5hex($self->{Pass}), $user->email);
        } elsif (my $email = $self->fb_email) {
            # we are logged in to facebook w/ proper authorization!
            return (_rand_md5hex($self->{Pass} . $email), $email);
        } else {
            # authentication failed
            $self->log_error("Invalid password for $self->{User}");
            return undef;
        }
    } elsif ($self->{Anon}) {
        # we're an anonymous session
        return _rand_md5hex('anonymous');
    }
    $self->log_error("Improper session credentials!") unless $quiet;
    return undef;
}

sub praux_user {
    my ($self) = @_;
    return Praux::user_by_email($self, $self->external_user);
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

1;
