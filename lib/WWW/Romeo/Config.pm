# LDIP::Config is where we're going to store all of our fun configuration options!
# BadNews::Config - Now w/ YAML!
# $Id: Config.pm,v 1.3 2005/04/07 12:58:19 corrupt Exp $

package WWW::Romeo::Config;

use base qw/WWW::Romeo/;
use YAML::Syck;
use Carp;

# make sure we stick this in here.. so we can do Yes = 1 and No = 0
$YAML::Syck::ImplicitTyping = 1;

sub new {
    my ($class, %attribs) = @_;
    my $self = bless(\%attribs, $class);
    if (-e $self->{ConfigFile}) {
        $self->{pyaml} = LoadFile($self->{ConfigFile});
    } else {
        croak "$self->{ConfigFile} doesn't exist...";
    }
    return $self;
}

sub AUTOLOAD {
    my ($self) = @_;
    my $option = $AUTOLOAD;
    $option =~ s/^.+::([\w\_]+)$/$1/g;
    if (exists($self->{pyaml}->{lc($option)})) {
        return $self->{pyaml}->{lc($option)};
    } else {
        return undef;
    }
}

sub dump_cfg {
    my ($self) = @_;
    my $cfg;
    foreach my $key (keys %{$self->{pyaml}}) {
        $cfg .= "$key: $self->{pyaml}->{$key}\n";
    }
    return $cfg;
}

sub DESTROY {
    my ($self) = @_;
    $self = {};
    return;
}
