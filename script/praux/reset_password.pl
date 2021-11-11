#!/usr/bin/env perl

my ($email) = @ARGV;

unless ($email) {
    die "Usage: reset_password.pl <email>\n";
}

use Praux;
my $praux = new Praux;

my $user = Praux->user_by_email($email);

if ($user) {
    my $pw = gen_pw(8);
    $user->password($pw);
    $user->update;
    print "$email\'s password reset to: $pw\n";
} else {
    die "Error: can't find user $email...\n";
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
