package Praux::Tools::ListResumes;

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
    
    my $order_by = $romeo->param('order_by') || 'instance';
    my $sort_order = $romeo->param('sort_order') || 'asc';
    
    # pagination
    my $page = $romeo->param('page') || 1;
    
    # rows.. maximum is 100
    my $rows = $romeo->param('rows') || 15;
    $rows = 100 if $rows > 100;
    
    $resume_rs = $self->all_resumes_paged($page, $order_by, $sort_order, $rows);
    $pager = $resume_rs->pager;
    
    my $to_serialize = {
        success => 1,
        order_by => $order_by,
        sort_order => $sort_order,
        max_page => $pager->last_page,
        current_page => $page,
        rows_per_page => $rows,
        result_count => $pager->total_entries,
        payload => [],
    };
    
    # get a hashref of resumes
    my $resumes = {};
        
    foreach my $resume ($resume_rs->all) {
        push(@{$to_serialize->{payload}}, {
            id => $resume->id,
            name => $resume->name,
            resume => $resume->instance . $self->c->COOKIE_DOMAIN,
            summary => $resume->summary,
            hit_count => $resume->hit_count,
            recent_title => $resume->recent_title,
            last_change => scalar(localtime($resume->modify_time)),
            last_change_epoch => $resume->modify_time,
            default_language => $resume->default_language,
        });
    }
    
    $to_serialize->{time_taken} = $romeo->time_taken;
    
    return $to_serialize;
}

1;
