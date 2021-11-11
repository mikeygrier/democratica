package Praux::Tools::ContentSearch;

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
    
    my $query = $romeo->param('q');
    my $order_by = $romeo->param('order_by') || 'resume';
    my $sort_order = $romeo->param('sort_order') || 'asc';
    
    # pagination
    my $page = $romeo->param('page') || 1;
    
    # rows.. maximum is 100
    my $rows = $romeo->param('rows') || 15;
    $rows = 100 if $rows > 100;
    
    unless ($query) {
        return {
            success => 0,
            error => 'Usage: /pt/content_search?q=<search_string>&order_by=<column_name>&sort_order=(asc|desc)&rows=<number_of_rows>&page=<page_number>',
        }
    }
    
    $resume_rs = $self->search_resumes_paged($query, $page, $order_by, $sort_order, $rows);
    $pager = $resume_rs->pager;
    
    my $to_serialize = {
        success => 1,
        q => $query,
        order_by => $order_by,
        sort_order => $sort_order,
        current_page => $page,
        result_count => $pager->total_entries,
        max_page => $pager->last_page,
        rows_per_page => $rows,
        payload => [],
    };
    
    # get a hashref of unique resumes
    my $resumes = {};
        
    foreach my $resume ($resume_rs->all) {
        push(@{$to_serialize->{payload}}, {
            id => $resume->id,
            name => $resume->name,
            summary => $resume->summary,
            resume => $resume->instance . $self->c->COOKIE_DOMAIN,
            hit_count => $resume->hit_count,
            last_change => scalar(localtime($resume->modify_time)),
            last_change_epoch => $resume->modify_time,
            owner => $resume->praux_user->id,
            default_language => $resume->default_language,
            default_theme => $resume->default_theme,
            score => $resume->votes->get_column('vote')->sum,
        });
    }
    
    $to_serialize->{time_taken} = $romeo->time_taken;
    
    return $to_serialize;
}

1;
