package Praux::Url::Register;

@ISA = ('Praux::Url::Component');

use Mail::Sender;
use Praux::Url::Component;
use Authen::Captcha;
use Apache2::Const qw/:common/;
use Apache2::Util qw/ht_time/;
use Digest::MD5 qw/md5_hex/;
use Carp;
use JSON;

# create one instance... for all to use ;)
my $json = JSON->new;

my $captcha = Authen::Captcha->new();

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

    $romeo->r->no_cache(1);

    # get rid of the first argument, used to dispatch through bN
    shift(@args);

    # unpack our arguments...
    my @uri = @args;
    my $page = $uri[0];

    if ($page) {
        # this is a registration confirmation!
        $romeo->r->content_type('text/html;charset=utf-8');
        
        # we just set a cookie before doing the rest..
        # TODO: pull the set of VERIFIED out of the confirm_registration template, and refactor this whole mess.
        my $token = $uri[1];
        my $password = $romeo->param('password');
        my $user = $self->user_by_verify_token($token);
        
        if ($password) {        
            if ($user && $user->authenticate($password)) {
                my $session = Praux::Session->new(
                    User        =>      $user->email,
                    Pass        =>      $password,
                );
            
                $cookie = Apache2::Cookie->new(  $romeo->r,     -name       =>      'romeo_auth',
                                                                -value      =>      $session->session_id,
                                                                -path       =>      '/',
                                                                -domain     =>      $romeo->c->COOKIE_DOMAIN,
                                             );

                $cookie->bake($romeo->r);
            }
        }
        
        $romeo->param('arg1' => $uri[1]);
        $romeo->param('arg2' => $uri[2]);
        $self->render_page($page);
    } else {
        # sending json or html?
        my $use_json = $romeo->param('json');
        if ($use_json) {
            $romeo->r->content_type('application-x/javascript');
        } else {
            $romeo->r->content_type('text/html;charset=utf-8');
        }
        
        
        if ($romeo->param('is_submit')) {
            # this is a submit...
            my @anticipated = qw/
                email       password        password_confirm
                captcha     common_name     accepted_terms_of_service
            /;
            my @required = qw/
                email       password        password_confirm
                captcha     common_name     accepted_terms_of_service
            /;

            # get everything we're anticipating getting...
            my %values = map { $_ => $romeo->param($_) || undef } @anticipated;

            if (my $error = $self->validate_input(\%values, \@required)) {
                # we're in error
                if ($use_json) {
                    print $json->objToJson({success => 0, error => $error});
                } else {
                    $romeo->param('error'     =>      $error);
                    $self->render_page('register');
                }
            } else {
                my $user;
                eval { 
                    $user = $self->schema->resultset('User')->create(
                        {   
                            email           =>      $values{email},
                            password        =>      $values{password},
                            common_name     =>      $values{common_name},
                            verify_token    =>      _rand_md5hex($values{email}),
                        }
                    );
                };

                if (my $error = $@) {
                    if ($use_json) {
                        print $json->objToJson({success => 0, error => "Unknown error: " . $error});
                    } else {
                        $romeo->param('error' =>      'Unknown error: ' . $error);
                        $self->render_page('register');
                    }
                } else {
                    $self->send_confirmation_email($user);
                    if ($use_json) {
                        print $json->objToJson({success => 1});
                    } else {
                        $self->render_page('register_success');
                    }
                }
            }
        } else {
            $self->render_page('register');
        }
    }
    return OK;
}

sub send_confirmation_email {
    my ($self, $user) = @_;

    # get the body!
    my $body;
    $self->romeo->template->process($self->romeo->theme . "/" . 'confirmation_email.htmlt', {user => $user, self => $self}, \$body);

    my $result = $mailer->MailMsg(
        {
            to      =>      $user->email,
            from    =>      'Praux <admin@praux.com>',
            subject =>      'Confirm your Praux account!',
            msg     =>      $body,
        }
    );

    if (ref($result) eq "Mail::Sender") {
        # success!
        return 1;
    } else {
        # failure!
        return undef;
    }
}

sub validate_input {
    my ($self, $values, $required) = @_;
    # before we do any more work, check the captcha..
    $captcha->data_folder($self->c->CAPTCHA_DATA_DIR);
    $captcha->output_folder($self->c->CAPTCHA_IMAGE_DIR);
    
    my $captcha_check = $captcha->check_code($values->{captcha}, $self->romeo->session->captcha_md5);
    $self->romeo->session->captcha_md5('__clear__');
    unless ($captcha_check > 0) {
        return "Failed Image Security";
    }

    # now check to make sure we have all our crap..
    foreach my $var (@$required) {
        if ($var eq "accepted_terms_of_service") {
            unless ($values->{$var}) {
                return "You must read and accept the terms of service to proceed!";
            }
        } else {
            unless (defined $values->{$var}) {
                return "Required attribute $var not found!";
            }
        }
    }  

    unless ($values->{email} =~ /[\w\.\%-]+\@[\w\.-]+\.[A-Za-z]{2,4}/o) {
        # invalid email address!
        return "Malformed e-mail address! ($values->{email})";
    }

    if ($self->user_by_email($values->{email})) {
        return "User with email address " . $values->{email} . " already exists.  Did you forget your password?";
    }

    unless ($values->{password} eq $values->{password_confirm}) {
        # password doesn't match password confirm!
        return "Passwords must match!";
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
