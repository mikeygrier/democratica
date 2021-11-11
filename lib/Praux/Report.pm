# the Praux reporting package!
package Praux::Report;

# we need to serialize the flot data
use JSON;
use Time::Local qw/timelocal_nocheck/;
my $json = new JSON;

sub new {
    my ($class, $praux) = @_;
    return bless ({praux => $praux}, $class);
}

sub _defaults {
    my ($self) = @_;
    return ((time - (3600 * 24) * 14), time, (3600 * 24), 5);
}

sub users_created_by_day {
    my ($self) = @_;
    my $day = 3600 * 24;
    my $first_time = 1258434000;
    my (@ubcd);
    for (my $i = $first_time; $i < time; $i += $day) {
        my $lower = $i - $day;
        my $rs = $self->{praux}->schema->resultset('User')->search_rs(
            {
                -and => [
                    create_time => { '>=', $lower },
                    create_time => { '<=', $i },
                ],
            }
        );
        my $localtime = localtime($lower);
        $localtime =~ s/00:00:00 //g;
        push (@ubcd, { date => $localtime, count => $rs->count });;
    }
    return (@ubcd);
}

sub users_created_by_week {
    my ($self) = @_;
    my $week = 3600 * 24 * 7;
    my $first_time = 1258347600;
    my (@ubcw);
    for (my $i = $first_time; $i < time; $i += $week) {
        my $lower = $i - $week;
        my $rs = $self->{praux}->schema->resultset('User')->search_rs(
            {
                -and => [
                    create_time => { '>=', $lower },
                    create_time => { '<=', $i },
                ],
            }
        );
        my $localtime = localtime($lower);
        $localtime =~ s/0\d:00:00 //g;
        push (@ubcw, { date => $localtime, count => $rs->count });
    }
    return (@ubcw);
}

sub most_active_users {
    my ($self, $rows) = @_;
    
    $rows = 10 unless $rows;
    
    my $sth = $self->dbh->prepare(qq/
        select acting_user, count(id) as tally from praux_log group by acting_user order by tally desc limit ?
    /);

    $sth->execute($rows);
    
    my @users;
    while (my $ar = $sth->fetchrow_arrayref) {
        push(@users, $self->{praux}->user_by_id($$ar[0]));
    }
    
    return(@users);
}

sub resume_views_robots_three_time {
    my ($self, $resume) = @_;
    my $dbstat = [];
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->this_hour_lower },
                is_robot => 1,
                resume => $resume,
            },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->today_lower },
                is_robot => 1,
                resume => $resume,
            },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->this_week_lower },
                is_robot => 1,
                resume => $resume,
            },
        }
    )->count);
    return $dbstat;
}

sub resume_views_people_three_time {
    my ($self, $resume) = @_;
    my $dbstat = [];
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->this_hour_lower },
                is_robot => 0,
                resume => $resume,
            },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->today_lower },
                is_robot => 0,
                resume => $resume,
            },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->this_week_lower },
                is_robot => 0,
                resume => $resume,
            },
        }
    )->count);
    return $dbstat;
}

sub resume_edits_three_time {
    my ($self, $resume) = @_;
    my $dbstat = [];
    push(@$dbstat, $self->praux->schema->resultset('Log')->search(
        {
            -and => {
                create_time => { '>', $self->this_hour_lower },
                resume => $resume,
            },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('Log')->search(
        {
            -and => {
                create_time => { '>', $self->today_lower },
                resume => $resume,
            },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('Log')->search(
        {
            -and => {
                create_time => { '>', $self->this_week_lower },
                resume => $resume,
            },
        }
    )->count);
    
    return $dbstat;
}

sub site_edits_three_time {
    my ($self) = @_;
    my $dbstat = [];
    push(@$dbstat, $self->praux->schema->resultset('Log')->search(
        {
            create_time => { '>', $self->this_hour_lower },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('Log')->search(
        {
            create_time => { '>', $self->today_lower },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('Log')->search(
        {
            create_time => { '>', $self->this_week_lower },
        }
    )->count);
    
    return $dbstat;
}

sub site_views_robots_three_time {
    my ($self) = @_;
    my $dbstat = [];
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->this_hour_lower },
                is_robot => 1,
            },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->today_lower },
                is_robot => 1,
            },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->this_week_lower },
                is_robot => 1,
            },
        }
    )->count);
    return $dbstat;
}

sub site_views_people_three_time {
    my ($self) = @_;
    my $dbstat = [];
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->this_hour_lower },
                is_robot => 0,
            },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->today_lower },
                is_robot => 0,
            },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->this_week_lower },
                is_robot => 0,
            },
        }
    )->count);
    return $dbstat;
}

sub site_views_three_time {
    my ($self) = @_;
    my $dbstat = [];
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->this_hour_lower },
            },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->today_lower },
            },
        }
    )->count);
    
    push(@$dbstat, $self->praux->schema->resultset('HitLog')->search(
        {
            -and => {
                create_time => { '>', $self->this_week_lower },
            },
        }
    )->count);
    return $dbstat;
}

# mmmhmm.. bounds.. bondage.. enjoy these temporal constraints
sub this_week_lower {
    my @t = localtime();
    my $t = time;
    my $sunday = $t - (86400 * $t[6]);

    # get sunday bloody sunday
    @t = localtime($sunday);
    return timelocal_nocheck(0, 0, 0, $t[3], $t[4], $t[5]);
}

sub today_lower {
    my @t = localtime();
    return timelocal_nocheck(0, 0, 0, $t[3], $t[4], $t[5]);
}

sub this_hour_lower {
    my @t = localtime();
    return timelocal_nocheck(0, 0, $t[2], $t[3], $t[4], $t[5]);
}

sub this_month_lower {
    my @t = localtime();
    return timelocal_nocheck(0, 0, 0, 1, $t[4], $t[5]);
}

sub top_referrers {
    my ($self, $lower, $upper, $count) = @_;
    unless ($lower) {
        ($lower, $upper) = $self->_defaults;
    }
    
    $count = 10 unless $count;

    my $cache_key = $self->praux->c->COOKIE_DOMAIN . "/SiteWide/TopReferrers/$count";
    $cache_key =~ s/\s+/\./g;
    
    my $top;
    unless ($top = $self->praux->memd->get($cache_key)) {
        $top = {};
        foreach my $user ($self->praux->schema->resultset('User')->search(
            {
                -and => {
                    create_time => { '>',  $lower },
                    create_time => { '<', $upper },
                    verified => "1",
                },
            })->all) {
            
            # go through all the referees... checking to make sure they have a resume and are verified..
            foreach my $referree ($user->referees->all) {
                if ($referree->verified && $referree->resume) {
                    if ($referree->resume->tip_blocks_left == 0) {
                        $top->{$user->id}++;
                    }
                }
            }
        }
        
        $self->praux->memd->set($cache_key, $top, 300) or warn "Error caching: $@\n";
    }
    
    return $top;
}

# the returned data structure needs to look like:
# [
#     {
#         flot_data_label => 'This',
#         flot_data => [1, 2, 3],
#     }
# ]
sub plot_top_languages {
    my ($self, $lower, $upper, $chunk_size, $count) = @_;
    
    unless ($lower) {
        ($lower, $upper, $chunk_size, $count) = $self->_defaults;
    }
    
    # we aren't even caching on perameters.. this is going to persist a while
    my $cache_key = $self->praux->c->COOKIE_DOMAIN . "/SiteWide/Graph/TopLanguages/$chunk_size";
    $cache_key =~ s/\s+/\./g;
    
    my $plots = [];
    unless ($plots = $self->praux->memd->get($cache_key)) {
        my (%resumes, @ordered_keys);
        my $sth = $self->dbh->prepare(qq/
            select label, sum(data) as total from praux_metrics FORCE INDEX (upper) where 
             metric_alias = ? and upper_bound between ? and ? group by label
             order by total desc limit ?;
        /);

        $sth->execute('resume-web_visits_lang', $lower, $upper, $count);

        my @labels;
        while (my $ar = $sth->fetchrow_arrayref) {
            push(@labels, $$ar[0]);
        }

        foreach my $label (@labels) {
            my @plot_data;
            # for each chunk..
            for (my $i = $lower; $i <= $upper; $i += $chunk_size) {
                my $sth = $self->dbh->prepare(qq/
                    select sum(data) from praux_metrics where 
                        upper_bound BETWEEN ? and ? AND
                        label = ? AND
                        metric_alias = ?
                /);

                $sth->execute($i, $i + $chunk_size, $label, 'resume-web_visits_lang');
                if (my $ar = $sth->fetchrow_arrayref) {
                    # millisecond epocs for javascript (flot)
                    push(@plot_data, [$i * 1000, $$ar[0]]) if defined($$ar[0]);
                }
            }
            push(@$plots, {
                flot_data_label => $label,
                flot_data => "[" .  join(', ', map { "[" . join(', ', @$_) . "]" } @plot_data) . "]"
            });
        }
    
        $self->praux->memd->set($cache_key, $plots, 1800) or warn "Error caching: $@\n";
    }
    
    return $plots;
}

sub plot_top_resumes {
    my ($self, $lower, $upper, $chunk_size, $count) = @_;
    
    unless ($lower) {
        ($lower, $upper, $chunk_size, $count) = $self->_defaults;
    }
    
    # we aren't even caching on perameters.. this is going to persist a while
    my $cache_key = $self->praux->c->COOKIE_DOMAIN . "/SiteWide/Graph/TopResumes/$chunk_size";
    $cache_key =~ s/\s+/\./g;
    
    my $plots = [];
    unless ($plots = $self->praux->memd->get($cache_key)) {
        my (%resumes, @ordered_keys);
        my $sth = $self->dbh->prepare(qq/
            select resume, instance, sum(data) as total from praux_metrics FORCE INDEX (upper) where 
             metric_alias = ? and upper_bound between ? and ? group by resume
             order by total desc limit ?;
        /);

        $sth->execute('resume-web_visits', $lower, $upper, $count);

        while (my $ar = $sth->fetchrow_arrayref) {
            $resumes{$$ar[0]} = $$ar[1];
            push(@ordered_keys, $$ar[0]);
        }

        foreach my $resume (@ordered_keys) {
            my @plot_data;
            # for each chunk..
            for (my $i = $lower; $i <= $upper; $i += $chunk_size) {
                my $sth = $self->dbh->prepare(qq/
                    select sum(data) from praux_metrics where 
                        upper_bound BETWEEN ? and ? AND
                        resume = ? AND
                        metric_alias = ?
                /);

                $sth->execute($i, $i + $chunk_size, $resume, 'resume-web_visits');
                if (my $ar = $sth->fetchrow_arrayref) {
                    # millisecond epocs for javascript (flot)
                    push(@plot_data, [$i * 1000, $$ar[0]]) if defined($$ar[0]);
                }
            }
            push(@$plots, {
                flot_data_label => "$resumes{$resume}" . $self->praux->c->COOKIE_DOMAIN,
                flot_data => "[" .  join(', ', map { "[" . join(', ', @$_) . "]" } @plot_data) . "]"
            });
        }
    
        $self->praux->memd->set($cache_key, $plots, 1800) or warn "Error caching: $@\n";
    }
    
    return $plots;
}

sub plot_activity {
    my ($self, $lower, $upper, $chunk_size) = @_;
    
    unless ($lower) {
        ($lower, $upper, $chunk_size) = $self->_defaults;
    }
    
    # we aren't even caching on perameters.. this is going to persist a while
    my $cache_key = $self->praux->c->COOKIE_DOMAIN . "/SiteWide/Graph/PrauxActivity/$chunk_size";
    $cache_key =~ s/\s+/\./g;
    
    my $plots = [];
    unless ($plots = $self->praux->memd->get($cache_key)) {
        my @plot_data;
        for (my $i = $lower; $i <= $upper; $i += $chunk_size) {
            my $sth = $self->dbh->prepare(qq/
                select sum(data) from praux_metrics where
                    upper_bound BETWEEN ? and ? AND
                    metric_alias = ?
            /);
            $sth->execute($i, $i + $chunk_size, 'resume-user_activity');
            
            if (my $ar = $sth->fetchrow_arrayref) {
                push(@plot_data, [$i * 1000, $$ar[0]]) if defined ($$ar[0]);
            }
        }
        
        push(@$plots, {
            flot_data_label => "Resume Edit Activity",
            flot_data => "[" .  join(', ', map { "[" . join(', ', @$_) . "]" } @plot_data) . "]",
        });
    
        $self->praux->memd->set($cache_key, $plots, 1800) or warn "Error caching: $@\n";
    }
    
    return $plots;
}

sub plot_hits {
    my ($self, $lower, $upper, $chunk_size) = @_;
    
    unless ($lower) {
        ($lower, $upper, $chunk_size) = $self->_defaults;
    }
    
    # we aren't even caching on perameters.. this is going to persist a while
    my $cache_key = $self->praux->c->COOKIE_DOMAIN . "/SiteWide/Graph/PrauxHits/$chunk_size";
    $cache_key =~ s/\s+/\./g;
    
    my $plots = [];
    unless ($plots = $self->praux->memd->get($cache_key)) {
        my @plot_data;
        for (my $i = $lower; $i <= $upper; $i += $chunk_size) {
            my $sth = $self->dbh->prepare(qq/
                select sum(data) from praux_metrics where
                    upper_bound BETWEEN ? and ? AND
                    metric_alias = ?
            /);
            $sth->execute($i, $i + $chunk_size, 'resume-web_visits');
            
            if (my $ar = $sth->fetchrow_arrayref) {
                push(@plot_data, [$i * 1000, $$ar[0]]) if defined ($$ar[0]);
            }
        }
        
        push(@$plots, {
            flot_data_label => "Total Resume Hits",
            flot_data => "[" .  join(', ', map { "[" . join(', ', @$_) . "]" } @plot_data) . "]",
        });
    
        $self->praux->memd->set($cache_key, $plots, 1800) or warn "Error caching: $@\n";
    }
    
    return $plots;
}

sub plot_resume_hits_content_type {
    my ($self, $lower, $upper, $chunk_size, $count) = @_;
    
    my $resume;
    unless ($resume = $self->praux->resume) {
        warn "plot_resume_hits_cached_vs_not called from a place with no resume.  it's so cold in here.\n";
        return undef;
    }
    
    unless ($lower) {
        ($lower, $upper, $chunk_size, $count) = $self->_defaults;
    }
    
    # we aren't even caching on perameters.. this is going to persist a while
    my $cache_key = $self->praux->c->COOKIE_DOMAIN . "/" . $self->praux->romeo->instance . "/Graph/ContentType/$chunk_size";
    $cache_key =~ s/\s+/\./g;
    
    my $plots = [];
    unless ($plots = $self->praux->memd->get($cache_key)) {
        my (%resumes, @ordered_keys);
        my $sth = $self->dbh->prepare(qq/
            select label, sum(data) as total from praux_metrics FORCE INDEX (upper) where 
             metric_alias = ? and resume = ? and upper_bound between ? and ? group by label
             order by total desc limit ?;
        /);

        $sth->execute('resume-web_visits_content_type', $resume->id, $lower, $upper, 5);

        my @labels;
        while (my $ar = $sth->fetchrow_arrayref) {
            push(@labels, $$ar[0]);
        }

        foreach my $label (@labels) {
            my @plot_data;
            # for each chunk..
            for (my $i = $lower; $i <= $upper; $i += $chunk_size) {
                my $sth = $self->dbh->prepare(qq/
                    select sum(data) from praux_metrics FORCE INDEX (upper) where 
                        upper_bound BETWEEN ? and ? AND
                        resume = ? AND
                        label = ? AND
                        metric_alias = ?
                /);

                $sth->execute($i, $i + $chunk_size, $resume->id, $label, 'resume-web_visits_content_type');
                if (my $ar = $sth->fetchrow_arrayref) {
                    # millisecond epocs for javascript (flot)
                    push(@plot_data, [$i * 1000, $$ar[0]]) if defined($$ar[0]);
                }
            }
            
            # get rid of everything after the first ; in the quotes
            $label =~ s/;[^"]+//g;
            
            # escape the quotes..
            $label =~ s/"/\\"/g;
            
            push(@$plots, {
                flot_data_label => $label,
                flot_data => "[" .  join(', ', map { "[" . join(', ', @$_) . "]" } @plot_data) . "]"
            });
        }
    
        $self->praux->memd->set($cache_key, $plots, 1800) or warn "Error caching: $@\n";
    }
    
    return $plots;
}

sub plot_resume_hits_lang {
    my ($self, $lower, $upper, $chunk_size, $count) = @_;
    
    my $resume;
    unless ($resume = $self->praux->resume) {
        warn "plot_resume_hits_cached_vs_not called from a place with no resume.  it's so cold in here.\n";
        return undef;
    }
    
    unless ($lower) {
        ($lower, $upper, $chunk_size, $count) = $self->_defaults;
    }
    
    # we aren't even caching on perameters.. this is going to persist a while
    my $cache_key = $self->praux->c->COOKIE_DOMAIN . "/" . $self->praux->romeo->instance . "/Graph/TopLanguages/$chunk_size";
    $cache_key =~ s/\s+/\./g;
    
    my $plots = [];
    unless ($plots = $self->praux->memd->get($cache_key)) {
        my (%resumes, @ordered_keys);
        my $sth = $self->dbh->prepare(qq/
            select label, sum(data) as total from praux_metrics FORCE INDEX (upper) where 
             metric_alias = ? and resume = ? and upper_bound between ? and ? group by label
             order by total desc limit ?;
        /);

        $sth->execute('resume-web_visits_lang', $resume->id, $lower, $upper, 5);

        my @labels;
        while (my $ar = $sth->fetchrow_arrayref) {
            push(@labels, $$ar[0]);
        }

        foreach my $label (@labels) {
            my @plot_data;
            # for each chunk..
            for (my $i = $lower; $i <= $upper; $i += $chunk_size) {
                my $sth = $self->dbh->prepare(qq/
                    select sum(data) from praux_metrics FORCE INDEX (upper) where 
                        upper_bound BETWEEN ? and ? AND
                        resume = ? AND
                        label = ? AND
                        metric_alias = ?
                /);

                $sth->execute($i, $i + $chunk_size, $resume->id, $label, 'resume-web_visits_lang');
                if (my $ar = $sth->fetchrow_arrayref) {
                    # millisecond epocs for javascript (flot)
                    push(@plot_data, [$i * 1000, $$ar[0]]) if defined($$ar[0]);
                }
            }
            push(@$plots, {
                flot_data_label => $label,
                flot_data => "[" .  join(', ', map { "[" . join(', ', @$_) . "]" } @plot_data) . "]"
            });
        }
    
        $self->praux->memd->set($cache_key, $plots, 1800) or warn "Error caching: $@\n";
    }
    
    return $plots;
}

sub plot_resume_hits_views {
    my ($self, $lower, $upper, $chunk_size, $count) = @_;
    
    my $resume;
    unless ($resume = $self->praux->resume) {
        warn "plot_resume_hits_cached_vs_not called from a place with no resume.  it's so cold in here.\n";
        return undef;
    }
    
    unless ($lower) {
        ($lower, $upper, $chunk_size, $count) = $self->_defaults;
    }
    
    # we aren't even caching on perameters.. this is going to persist a while
    my $cache_key = $self->praux->c->COOKIE_DOMAIN . "/" . $self->praux->romeo->instance . "/Graph/Views/$chunk_size";
    $cache_key =~ s/\s+/\./g;
    
    my $plots = [];
    unless ($plots = $self->praux->memd->get($cache_key)) {
        my (%resumes, @ordered_keys);
        my $sth = $self->dbh->prepare(qq/
            select label, sum(data) as total from praux_metrics FORCE INDEX (upper) where 
             metric_alias = ? and resume = ? and upper_bound between ? and ? group by label
             order by total desc limit ?;
        /);

        $sth->execute('resume-web_visits_views', $resume->id, $lower, $upper, 5);

        my @labels;
        while (my $ar = $sth->fetchrow_arrayref) {
            push(@labels, $$ar[0]);
        }

        foreach my $label (@labels) {
            my @plot_data;
            # for each chunk..
            for (my $i = $lower; $i <= $upper; $i += $chunk_size) {
                my $sth = $self->dbh->prepare(qq/
                    select sum(data) from praux_metrics FORCE INDEX (upper) where 
                        upper_bound BETWEEN ? and ? AND
                        resume = ? AND
                        label = ? AND
                        metric_alias = ?
                /);

                $sth->execute($i, $i + $chunk_size, $resume->id, $label, 'resume-web_visits_views');
                if (my $ar = $sth->fetchrow_arrayref) {
                    # millisecond epocs for javascript (flot)
                    push(@plot_data, [$i * 1000, $$ar[0]]) if defined($$ar[0]);
                }
            }
            push(@$plots, {
                flot_data_label => $label,
                flot_data => "[" .  join(', ', map { "[" . join(', ', @$_) . "]" } @plot_data) . "]"
            });
        }
    
        $self->praux->memd->set($cache_key, $plots, 1800) or warn "Error caching: $@\n";
    }
    
    return $plots;
}

sub plot_resume_hits_robots_vs_not {
    my ($self, $lower, $upper, $chunk_size, $count) = @_;
    
    my $resume;
    unless ($resume = $self->praux->resume) {
        warn "plot_resume_hits_cached_vs_not called from a place with no resume.  it's so cold in here.\n";
        return undef;
    }
    
    unless ($lower) {
        ($lower, $upper, $chunk_size, $count) = $self->_defaults;
    }
    
    # we aren't even caching on perameters.. this is going to persist a while
    my $cache_key = $self->praux->c->COOKIE_DOMAIN . "/" . $self->praux->romeo->instance . "/Graph/RobotsVsNot/$chunk_size";
    $cache_key =~ s/\s+/\./g;
    
    my $plots = [];
    unless ($plots = $self->praux->memd->get($cache_key)) {
        my (%resumes, @ordered_keys);
        my $sth = $self->dbh->prepare(qq/
            select label, sum(data) as total from praux_metrics FORCE INDEX (upper) where 
             metric_alias = ? and resume = ? and upper_bound between ? and ? group by label
             order by total desc limit ?;
        /);

        $sth->execute('resume-web_visits_robots', $resume->id, $lower, $upper, 2);

        my @labels;
        while (my $ar = $sth->fetchrow_arrayref) {
            push(@labels, $$ar[0]);
        }

        foreach my $label (@labels) {
            my @plot_data;
            # for each chunk..
            for (my $i = $lower; $i <= $upper; $i += $chunk_size) {
                my $sth = $self->dbh->prepare(qq/
                    select sum(data) from praux_metrics FORCE INDEX (upper) where 
                        upper_bound BETWEEN ? and ? AND
                        resume = ? AND
                        label = ? AND
                        metric_alias = ?
                /);

                $sth->execute($i, $i + $chunk_size, $resume->id, $label, 'resume-web_visits_robots');
                if (my $ar = $sth->fetchrow_arrayref) {
                    # millisecond epocs for javascript (flot)
                    push(@plot_data, [$i * 1000, $$ar[0]]) if defined($$ar[0]);
                }
            }
            push(@$plots, {
                flot_data_label => $label,
                flot_data => "[" .  join(', ', map { "[" . join(', ', @$_) . "]" } @plot_data) . "]"
            });
        }
    
        $self->praux->memd->set($cache_key, $plots, 1800) or warn "Error caching: $@\n";
    }
    
    return $plots;
}

sub plot_resume_hits_cached_vs_not {
    my ($self, $lower, $upper, $chunk_size, $count) = @_;
    
    my $resume;
    unless ($resume = $self->praux->resume) {
        warn "plot_resume_hits_cached_vs_not called from a place with no resume.  it's so cold in here.\n";
        return undef;
    }
    
    unless ($lower) {
        ($lower, $upper, $chunk_size, $count) = $self->_defaults;
    }
    
    # we aren't even caching on perameters.. this is going to persist a while
    my $cache_key = $self->praux->c->COOKIE_DOMAIN . "/" . $self->praux->romeo->instance . "/Graph/CachedVsNot/$chunk_size";
    $cache_key =~ s/\s+/\./g;
    
    my $plots = [];
    unless ($plots = $self->praux->memd->get($cache_key)) {
        my (%resumes, @ordered_keys);
        my $sth = $self->dbh->prepare(qq/
            select label, sum(data) as total from praux_metrics FORCE INDEX (upper) where 
             metric_alias = ? and resume = ? and upper_bound between ? and ? group by label
             order by total desc limit ?;
        /);

        $sth->execute('resume-web_visits_cache', $resume->id, $lower, $upper, 2);

        my @labels;
        while (my $ar = $sth->fetchrow_arrayref) {
            push(@labels, $$ar[0]);
        }

        foreach my $label (@labels) {
            my @plot_data;
            # for each chunk..
            for (my $i = $lower; $i <= $upper; $i += $chunk_size) {
                my $sth = $self->dbh->prepare(qq/
                    select sum(data) from praux_metrics FORCE INDEX (upper) where 
                        upper_bound BETWEEN ? and ? AND
                        resume = ? AND
                        label = ? AND
                        metric_alias = ?
                /);

                $sth->execute($i, $i + $chunk_size, $resume->id, $label, 'resume-web_visits_cache');
                if (my $ar = $sth->fetchrow_arrayref) {
                    # millisecond epocs for javascript (flot)
                    push(@plot_data, [$i * 1000, $$ar[0]]) if defined($$ar[0]);
                }
            }
            push(@$plots, {
                flot_data_label => $label,
                flot_data => "[" .  join(', ', map { "[" . join(', ', @$_) . "]" } @plot_data) . "]"
            });
        }
    
        $self->praux->memd->set($cache_key, $plots, 1800) or warn "Error caching: $@\n";
    }
    
    return $plots;
}

sub plot_resume_hits_humans_only {
    my ($self, $lower, $upper, $chunk_size) = @_;
    
    my $resume;
    unless ($resume = $self->praux->resume) {
        warn "plot_resume_hits called from a place with no resume.  it's so cold in here.\n";
        return undef;
    }
    
    unless ($lower) {
        ($lower, $upper, $chunk_size) = $self->_defaults;
    }
    
    # we aren't even caching on perameters.. this is going to persist a while
    my $cache_key = $self->praux->c->COOKIE_DOMAIN . "/" . $self->praux->romeo->instance . "/Graph/PrauxHitsHumansOnly/$chunk_size";
    $cache_key =~ s/\s+/\./g;
    
    my $plots = [];
    unless ($plots = $self->praux->memd->get($cache_key)) {
        my @plot_data;
        for (my $i = $lower; $i <= $upper; $i += $chunk_size) {
            my $sth = $self->dbh->prepare(qq/
                select sum(data) from praux_metrics FORCE INDEX (upper) where
                    upper_bound BETWEEN ? and ? AND
                    label = ? AND 
                    resume = ? AND
                    metric_alias = ?
            /);
            $sth->execute($i, $i + $chunk_size, 'Resume Visits By Humans', $resume->id, 'resume-web_visits_robots');
            
            if (my $ar = $sth->fetchrow_arrayref) {
                push(@plot_data, [$i * 1000, $$ar[0]]) if defined ($$ar[0]);
            }
        }
        
        push(@$plots, {
            flot_data_label => "Resume Visits By Humans [" . $self->praux->romeo->instance . "]",
            flot_data => "[" .  join(', ', map { "[" . join(', ', @$_) . "]" } @plot_data) . "]",
        });
    
        $self->praux->memd->set($cache_key, $plots, 1800) or warn "Error caching: $@\n";
    }
    
    return $plots;
}

sub plot_resume_hits {
    my ($self, $lower, $upper, $chunk_size) = @_;
    
    my $resume;
    unless ($resume = $self->praux->resume) {
        warn "plot_resume_hits called from a place with no resume.  it's so cold in here.\n";
        return undef;
    }
    
    unless ($lower) {
        ($lower, $upper, $chunk_size) = $self->_defaults;
    }
    
    # we aren't even caching on perameters.. this is going to persist a while
    my $cache_key = $self->praux->c->COOKIE_DOMAIN . "/" . $self->praux->romeo->instance . "/Graph/PrauxHits/$chunk_size";
    $cache_key =~ s/\s+/\./g;
    
    my $plots = [];
    unless ($plots = $self->praux->memd->get($cache_key)) {
        my @plot_data;
        for (my $i = $lower; $i <= $upper; $i += $chunk_size) {
            my $sth = $self->dbh->prepare(qq/
                select sum(data) from praux_metrics FORCE INDEX (upper) where
                    upper_bound BETWEEN ? and ? AND
                    resume = ? AND
                    metric_alias = ?
            /);
            $sth->execute($i, $i + $chunk_size, $resume->id, 'resume-web_visits');
            
            if (my $ar = $sth->fetchrow_arrayref) {
                push(@plot_data, [$i * 1000, $$ar[0]]) if defined ($$ar[0]);
            }
        }
        
        push(@$plots, {
            flot_data_label => "Total Resume Hits [" . $self->praux->romeo->instance . "]",
            flot_data => "[" .  join(', ', map { "[" . join(', ', @$_) . "]" } @plot_data) . "]",
        });
    
        $self->praux->memd->set($cache_key, $plots, 1800) or warn "Error caching: $@\n";
    }
    
    return $plots;
}

sub dbh {
    my ($self) = @_;
    return $self->praux->schema->storage->dbh;
}

sub praux {
    my ($self) = @_;
    return $self->{praux};
}

1;