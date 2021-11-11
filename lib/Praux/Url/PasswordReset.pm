# $Id: Page.pm 441 2006-12-11 21:32:47Z corrupt $
package Praux::Url::PasswordReset;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use Mail::Sender;

sub handle_request {
    my ($self, $romeo, @uri) = @_;

    $romeo->r->content_type('text/html;charset=utf-8');
    my $e = $romeo->param('e');
    if ($e) {
        my $u = $self->user_by_email($e);
        if ($u) {
            unless ($u->preference('com.praux.pwresetoff')) {
                my $pw = gen_pw(8);
                $u->password($pw);
                $u->update;
                $self->send_pw_reset_email($u, $pw);
            }
        }
        $self->render_page('password_reset', { show_success => 1 });
    } else {
        $self->render_page('password_reset');
    }
    
    return OK;
}

sub send_pw_reset_email {
    my ($self, $user, $pass) = @_;

    # get the body!
    my $body;
    $self->romeo->template->process($self->romeo->theme . "/" . 'password_reset_email.htmlt', {user => $user, self => $self, pass => $pass}, \$body);

    my $result = $self->mailer->MailMsg(
        {
            to      =>      $user->email,
            from    =>      'Praux <admin@praux.com>',
            subject =>      'Your Praux.com password has been reset!',
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

1;
