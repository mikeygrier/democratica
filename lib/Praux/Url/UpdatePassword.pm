package Praux::Url::UpdatePassword;

@ISA = ('Praux::Url::Component');

use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw/ht_time/;
use Digest::MD5 qw/md5_hex/;
use Carp;

sub handle_request {
    my ($self, $romeo, @args) = @_;

    $romeo->r->no_cache(1);

    # get rid of the first argument, used to dispatch through bN
    shift(@args);

    # unpack our arguments...
    my @uri = @args;

    # sending json or html?
    $romeo->r->content_type('text/html;charset=utf-8');
    
    
    if ($romeo->param('is_submit')) {
        # this is a submit...
        my @anticipated = qw/
            current_password    password
            confirm
        /;
        my @required = qw/
            current_password    password
            confirm
        /;

        # get everything we're anticipating getting...
        my %values = map { $_ => $romeo->param($_) || undef } @anticipated;

        if (my $error = $self->validate_input(\%values, \@required)) {
            # we're in error
            $romeo->param('error'     =>      $error);
            $self->render_page('update_password');
        } else {
            my $user = $self->active_user;
            if ($user) {
                if ($user->authenticate($values{current_password})) {
                    if ($values{password} && ($values{password} eq $values{confirm})) {
                        eval { 
                            $user->password($values{password});
                            $user->update();
                        };

                        if (my $error = $@) {
                            $romeo->param('error' =>      'Unknown error: ' . $error);
                            $self->render_page('update_password');
                        } else {
                            $romeo->r->headers_out->set(Location => '/');
                            return REDIRECT;
                        }
                    } else {
                        $romeo->param(error => "Passwords didn't match!");
                        $self->render_page('update_password');
                    }
                } else {
                    $romeo->param(error => "Invalid current password!");
                    $self->render_page('update_password');
                } 
            } else {
                $romeo->param(error => "You must be logged in to use this tool!");
                $self->render_page('update_password');
            }
        }
    } else {
        $self->render_page('update_password');
    }
    return OK;
}

sub validate_input {
    my ($self, $values, $required) = @_;

    # now check to make sure we have all our crap..
    foreach my $var (@$required) {
        unless (defined $values->{$var}) {
            return "Required attribute $var not found!";
        }
    }  

    return undef;
}



sub time {
    my ($self) = @_;
    return time;
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
