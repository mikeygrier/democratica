package Praux::Url::EditResume;

@ISA = ('Praux::Url::Component');

use Mail::Sender;
use Praux::Url::Component;
use Praux::Util::Zimbra;
use Apache2::Const qw/:common/;
use Apache2::Util qw/ht_time/;
use Digest::MD5 qw/md5_hex/;
use Carp;

$Mail::Sender::NO_X_MAILER = 1;

my $mailer = Mail::Sender->new(
    {    
        smtp        =>      'mail.mg2.org',
        from        =>      'admin@praux.com',
        headers     =>      {
            'X-Mailer'      =>      'Praux v0.05',
        }
    }
);

sub handle_request {
    my ($self, $romeo, @args) = @_;

    if (!$self->resume) {
        $romeo->r->content_type('text/html;charset=utf-8');
        $romeo->render_error("This resume doesn't exist yet!  You can't edit it!");
        return OK;
    }

    if (!$self->active_user || ($self->resume->praux_user->id != $self->active_user->id)) {
        $romeo->r->content_type('text/html;charset=utf-8');
        $romeo->render_error('Access Denied -- You do not own this resume, or have not created this resume!');
        return OK;
    }

    $romeo->r->no_cache(1);

    # get rid of the first argument, used to dispatch through bN
    shift(@args);

    # unpack our arguments...
    my @uri = @args;

    # sending json or html?
    $romeo->r->content_type('text/html;charset=utf-8');
  
    my $resume = $self->resume;
    
    my $zimbra = Praux::Util::Zimbra->new(
        resume => $resume,
    );
    
    # delete this resume
    if ($romeo->param('delete') == 1) {
        $zimbra->disable_mailmask;
        $resume->content_blocks->delete();
        $resume->delete();
        $romeo->r->headers_out->set(Location => '/');
        return REDIRECT;
    }
    
    if ($romeo->param('is_submit')) {
        # this is a submit...
        my @anticipated = qw/
            name        phone           email
            address
        /;
        my @required = qw/
            name        email
        /;

        # get everything we're anticipating getting...
        my %values = map { $_ => $romeo->param($_) || undef } @anticipated;

        if (my $error = $self->validate_input(\%values, \@required)) {
            # we're in error
            $romeo->param('error'     =>      $error);
            $self->render_page('edit_resume');
        } else {
            my $email_changed = $values{email} eq $resume->email ? 0 : 1;
            my $reenable_mailmask = 0;
            if ($zimbra->mailmask_enabled && $email_changed) {
                $reenable_mailmask = 1;
                $zimbra->disable_mailmask;
            }

            eval { 
                $resume->set_columns(
                    {
                        name => $values{name},
                        email => $values{email},
                        phone => $values{phone},
                        address => $values{address},
                        instance => $self->instance,
                    }
                );
                $resume->update();
            };

            if (my $error = $@) {
                $romeo->param('error' =>      'Unknown error: ' . $error);
                $self->render_page('edit_resume');
            } else {
                # turn this back on with new data if applicable!
                $zimbra->enable_mailmask if $reenable_mailmask;
                
                $self->clear_all_cache();
                $self->log_action({
                    action => __PACKAGE__,
                    resume => $self->resume,
                    instance => $self->instance,
                    acting_user => $self->active_user->id,
                });
                $romeo->r->headers_out->set(Location => '/');
                return REDIRECT;
            }
        }
    } else {
        $self->render_page('edit_resume', {mailmask_enabled => $zimbra->mailmask_enabled});
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

    unless ($values->{email} =~ /[\w\.\%-]+\@[\w\.-]+\.[A-Za-z]{2,4}/o) {
        # invalid email address!
        return "Malformed e-mail address! ($values->{email})";
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
