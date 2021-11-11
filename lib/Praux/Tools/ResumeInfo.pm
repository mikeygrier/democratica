package Praux::Tools::ResumeInfo;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use JSON;

my $json = new JSON;

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    
    my $to_serialize = {
        success => 1,
        payload => [],
    };
    
    my @resumes = $romeo->param('resume');
    
    unless (scalar(@resumes)) {
        return {
            success => 0,
            error => 'Usage: /pt/resume_info?resume=<praux_resume>&resume=<praux_resume> e.g. john.doe.praux.com',
        }
    }
    
    foreach my $resume_string (@resumes) {
        $resume_string =~ s/^(.+)\.praux\.com/$1/g;
        my $resume = $self->resume_by_instance($resume_string);
        if ($resume) {
            push(@{$to_serialize->{payload}}, $self->resume_info($resume));
        } else {
            push(@{$to_serialize->{payload}}, {
                resume => $resume_string . $self->c->COOKIE_DOMAIN,
                message => "Resume does not exist",
            });
        }
    }
    
    $to_serialize->{time_taken} = $romeo->time_taken;
    
    return $to_serialize;
}

1;
