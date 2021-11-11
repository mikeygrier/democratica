# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::RegisterTwo;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use LWP::UserAgent;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use JSON;
use Praux;
use Mail::Sender;

$Mail::Sender::NO_X_MAILER = 1;

my $mailer = Mail::Sender->new(
    {    
        smtp        =>      'mail.mg2.org',
        from        =>      'admin@praux.com',
        headers     =>      {
            'X-Mailer'      =>      'Praux v' . $Praux::VERSION,
        }
    }
);

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    my $page = $uri[1];

    $romeo->r->no_cache(1);
    $romeo->r->content_type('text/html;charset=utf-8');

    # write these values into the session..
    $self->session->register_email($romeo->param('register_email'));
    $self->session->register_common_name($romeo->param('register_common_name'));
    $self->session->accepted_terms_of_service($romeo->param('accepted_terms_of_service'));
    
    # make sure we supplied an email
    unless ($self->session->register_email) {
        $self->render_page('register', { error => "You must specify a valid email address to proceed!" });
        return OK;
    }

    # make sure we supplied a common name!
    unless ($self->session->register_common_name) {
        $self->render_page('register', { error => "You must specify your name to proceed!" });
        return OK;
    }

    if ($romeo->param('register_password')) {    
        if ($romeo->param('register_password') eq $self->session->register_password) {
            $self->session->final_password($self->session->register_password);
        } else {
            $self->session->register_password('__clear__');
            $self->render_page('register', { error => "Passwords Don't Match"});
            return OK;
        }
    } elsif ($romeo->param('password')) {
        if ($romeo->param('password') eq $romeo->param('password_confirm')) {
            $self->session->final_password($romeo->param('password'));
        } else {
            $self->session->register_password('__clear__');
            $self->render_page('register', { error => "Passwords Don't Match"});
            return OK;
        }
    }

    # make sure we agree to the TOS!
    unless ($self->session->accepted_terms_of_service) {
        $self->render_page('register', { error => "You must accept the Praux.com Terms Of Service to proceed!" });
        return OK;
    }
    
    # ok, we're a local provision, so we dont have to do any of the keying..
    my $provisioner = $self->provisioner_by_id(1);
    my %params;
    $params{user_cn} = $self->session->register_common_name;
    $params{referrer} = $self->session->register_referral;
    $params{user_email} = $self->session->register_email;
    $params{user_password} = $self->session->final_password;
    $params{provision_hash} = $provisioner->provision_hash;
    $params{provision_key} = $provisioner->provision_key;
    
    my $ua = new LWP::UserAgent;
    $ua->agent('Praux.com v' . $self->version);
    
    my $user;
    my $resp = $ua->post('https://ssl' . $self->romeo->c->COOKIE_DOMAIN . '/pt/pv.json', \%params);
    if ($resp->is_success) {
        my $json = new JSON;
        my $hr = $json->decode($resp->decoded_content);
        if ($hr->{success} == 0) {
            $self->render_page('register', { error => $hr->{error} });
            return OK;
        } else {
            $user = $self->user_by_id($hr->{user_provision}->{id});
        }
    } else {
        $self->render_page('register',a { error => "HTTP Error: " . $resp->status_line });
        return OK;
    }
    
    $self->session->register_common_name('__clear__');
    $self->session->register_email('__clear__');
    $self->session->final_password('__clear__');;
    $self->session->accepted_terms_of_service('__clear__');
    $self->session->passed_register_captcha('__clear__');
    $self->session->register_referral('__clear__') if $self->session->register_referral;
    
    # send the email
    $self->send_confirmation_email($user);
    
    $self->render_page('register_success');
    return OK;
}

sub send_confirmation_email {
    my ($self, $user) = @_;

    # get the body!
    my $body;
    $self->romeo->template->process($self->romeo->theme . "/" . 'new_resume_email.htmlt', {user => $user, self => $self}, \$body);

    my $result = $mailer->MailMsg(
        {
            to      =>      $user->email,
            from    =>      'Michael Gregorowicz <michael@praux.com>',
            subject =>      'Welcome To Praux.com',
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


1;