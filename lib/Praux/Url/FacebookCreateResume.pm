# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::FacebookCreateResume;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use LWP::UserAgent;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use JSON;
use Praux;
use Praux::Util::Zimbra;
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

    unless ($self->fb_email) {
        # no facebook session w/ email perms.. gtfo!
        $romeo->r->headers_out->set(Location => $self->root_url);
        return REDIRECT;
    }

    my $instance = lc($romeo->param('instance'));
    
    # remove leading and trailing .'s and whitespace and swap all illegal chars for hyphens!
    $instance =~ s/\.+$//g;
    $instance =~ s/^\.+//g;
    $instance =~ s/\s+//g;
    $instance =~ s/[^A-Za-z0-9\.\-]/-/g;

    if ($instance =~ /^\d+$/) {
        $instance = undef;
    }
    
    # write these values into the session..
    $self->session->register_email($self->fb_email);
    $self->session->register_common_name($romeo->param('name'));
    $self->session->accepted_terms_of_service($romeo->param('accepted_terms_of_service'));
    $self->session->resume_instance($instance);
    
    # make sure we agree to the TOS!
    unless ($self->session->accepted_terms_of_service) {
        $self->render_page('fb_create_resume', { error => "You must accept the Praux.com Terms Of Service to proceed!" });
        return OK;
    } 
      
    # make sure we have an instance!
    unless ($self->session->resume_instance) {
        $self->render_page('fb_create_resume', { error => "You must specify a valid resume instance to proceed!" });
        return OK;
    }
    # make sure we supplied an email - we should have one but what the hey.
    unless ($self->session->register_email) {
        $self->render_page('fb_create_resume', { error => "You must specify a valid email address to proceed!" });
        return OK;
    }

    # make sure we supplied a common name!
    unless ($self->session->register_common_name) {
        $self->render_page('fb_create_resume', { error => "You must specify your name to proceed!" });
        return OK;
    }

    if ($self->resume_by_instance($self->session->resume_instance)) {
        $self->render_page('fb_create_resume', { error => "Instance " . $self->session->resume_instance . " is already taken!" });
        return OK;
    }
	
    # no password here.. but a random 16 character bad boy.  no brute force backdoors.
    $self->session->final_password(gen_pw(16));

    # ok, we're a local provision, so we dont have to do any of the keying..
    my $provisioner = $self->provisioner_by_id(1);
    my %params;
    
    # provisioner authentication
    $params{provision_hash} = $provisioner->provision_hash;
    $params{provision_key} = $provisioner->provision_key;
    
    # user parameters
    $params{user_cn} = $self->session->register_common_name;
    $params{referrer} = $self->session->register_referral;
    $params{user_email} = $self->session->register_email;
    $params{user_password} = $self->session->final_password;
    $params{external_id} = $self->fb->users->get_logged_in_user;
    $params{external_type} = 'fb';
    $params{verify_email} = 0;
    
    # resume parameters
    $params{create_resume} = 1;
    $params{resume_instance} = $self->session->resume_instance;
    $params{resume_name} = $self->session->register_common_name;
    $params{resume_email} = $self->session->register_email;
    $params{default_language} = ($self->fb_locale)[0];
    
    my $ua = new LWP::UserAgent;
    $ua->agent('Praux.com v' . $self->version);
    
    my $user;
    my $resp = $ua->post('https://ssl' . $self->romeo->c->COOKIE_DOMAIN . '/pt/pv.json', \%params);
    if ($resp->is_success) {
        my $json = new JSON;
        my $hr = $json->decode($resp->decoded_content);
        use Data::Dumper;
        warn Dumper($hr);
        if ($hr->{success} == 0) {
            $self->render_page('fb_create_resume', { error => $hr->{error} });
            return OK;
        } else {
            $user = $self->user_by_id($hr->{user_provision}->{id});
        }
    } else {
        $self->render_page('fb_create_resume', { error => "HTTP Error: " . $resp->status_line });
        return OK;
    }
    
    $self->session->register_common_name('__clear__');
    $self->session->register_email('__clear__');
    $self->session->final_password('__clear__');;
    $self->session->accepted_terms_of_service('__clear__');
    $self->session->passed_register_captcha('__clear__');
    $self->session->register_referral('__clear__');
    $self->session->resume_instance('__clear__');
    
    # send the email
    $self->send_confirmation_email($user);
    
    my $resume = $user->resume;
    
    # at Vera's suggestion.. mail masking by default (here too)
    my $zimbra = Praux::Util::Zimbra->new( resume => $resume );
    $zimbra->enable_mailmask;
    $user->preference('com.praux.showmailmask', 1);
    $user->preference('com.praux.publish_resume', 1);
    
    # re-evaluate the sitch and dispatch :D
    $romeo->r->headers_out->set(Location => '/fbpostauth/');
    return REDIRECT;
}

sub gen_pw {
    my ($c) = @_;

    my @chars = (A...Z, a...z, 0...9);
    my @need_one = ([A...Z], [a...z], [0...9]);

    my $rc = $c - scalar(@need_one);

    my ($pw, $la);
    my $ni = 0;
    for (my $i = $rc; $i > 0; --$i) {
        $na = $chars[sprintf('%d', rand(scalar(@chars)))];

        if ($na eq $la) {
            $i++;
            next;
        } else {
            $pw .= $na;
            $la = $na;
        }

        if (rand(10) % 2 && $ni <= $#need_one) {
            $na = $need_one[$ni]->[sprintf('%d', rand(scalar(@{$need_one[$ni]})))];

            if ($na eq $la) {
                next;
            } else {
                $pw .= $na;
                $la = $na;
                $ni++;
            }
        }
    }

    while ($ni <= $#need_one) {
        $na = $need_one[$ni]->[sprintf('%d', rand(scalar(@{$need_one[$ni]})))];
        if ($na eq $la) {
            $i++;
            next;
        } else {
            $pw .= $na;
            $la = $na;
            $ni++;
        }
    }

    return $pw;
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