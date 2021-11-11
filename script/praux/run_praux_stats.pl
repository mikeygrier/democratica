#!/usr/bin/env perl

print "[startup] (P.c) Praux.com statisics generator startup.\n";

use Praux;
my $praux = Praux->new();
print "[info] Found " . $praux->schema->resultset('Resume')->count . " resumes to run stats for..\n";
my $dbh = $praux->schema->storage->dbh;
unless ($dbh) {
    die "Error retrieving generic dbh from DBIx::Class::Schema\n";
}

my $first_time = 1258470000;
my $last_time = get_last_time();
my $last_ptime = get_last_ptime();
my $seg_size = 900;

print "[info] Using origin time stamp: " . localtime($first_time) . "\n";
print "[info] Using final timestamp: " . localtime($last_time) . "\n";

if ($last_ptime) {
    print "[info] Last processed chunk: " . localtime($last_ptime) . "\n";
    $last_ptime += $seg_size;
} else {
    print "[concern] Uhm.. did something happen to our stats?!\n";
    $last_ptime = $first_time + $seg_size;
}

# $last_ptime is now the current block..

foreach my $resume ($praux->schema->resultset('Resume')->all) {
    # start with the current block of datas, do not process a block if the upper bound of the block is in the future
    print "[info] gathering extra information about resume " . $resume->instance . "\n";

    my @langs;
    # get top languages for this resume
    my $sth = $dbh->prepare(qq/
        select language, count(language) as count from praux_hitlog where resume = ? 
            group by language order by count desc limit 5
    /);

    $sth->execute($resume->id);
    while (my $ar = $sth->fetchrow_arrayref) {
        push(@langs, $$ar[0]);
    }

    print "[info] done gathering languages for resume " . $resume->instance . "\n";

    my @content_type;
    # get top remote addresses for this resume
    my $sth = $dbh->prepare(qq/
        select content_type, count(content_type) as count from praux_hitlog where resume = ? 
            group by content_type order by count desc
    /);

    $sth->execute($resume->id);
    while (my $ar = $sth->fetchrow_arrayref) {
        push(@content_type, $$ar[0]);
    }

    print "[info] done gathering content_types for resume " . $resume->instance . "\n";

    my @views;
    # get top remote addresses for this resume
    my $sth = $dbh->prepare(qq/
        select view, count(view) as count from praux_hitlog where resume = ? 
            group by view order by count desc
    /);

    $sth->execute($resume->id);
    while (my $ar = $sth->fetchrow_arrayref) {
        next if $$ar[0] eq "robots.txt";
        push(@views, $$ar[0]);
    }

    print "[info] done gathering views for resume " . $resume->instance . "\n";

    print "[info] starting stats loop for " . $resume->instance . "\n";
    for (my $i = $last_ptime; $i <= $last_time && $i <= (time + $seg_size); $i += $seg_size) {
        process_web_visits($resume, $i, $i + $seg_size);
        process_web_visits_by_robot($resume, $i, $i + $seg_size);
        process_web_visits_by_cache($resume, $i, $i + $seg_size);
        process_user_activity($resume, $i, $i + $seg_size);
        process_visits_by_language($resume, $i, $i + $seg_size, \@langs);
        process_visits_by_views($resume, $i, $i + $seg_size, \@views);
        process_visits_by_content_type($resume, $i, $i + $seg_size, \@content_type);
    }
    print "[info] finished stats loop for " . $resume->instance . "\n\n";

}

sub get_last_ptime {
    my ($name) = @_;

    my $sth;
    if ($name) {
        $sth = $dbh->prepare("select max(lower_bound) from praux_metrics where metric_alias = ?");
        $sth->execute($name);
    } else {
        $sth = $dbh->prepare("select max(lower_bound) from praux_metrics");
        $sth->execute;
    }

    my $ar = $sth->fetchrow_arrayref;
    return $$ar[0];
}

sub get_last_time {
    my $sth = $dbh->prepare("select max(create_time) from praux_hitlog");
    $sth->execute;
    my $ar = $sth->fetchrow_arrayref;
    return $$ar[0];
}

sub process_user_activity {
    my ($resume, $lower, $upper) = @_;
    my $sth = $dbh->prepare("select count(id) from praux_log where resume = ? and create_time between ? and ?");
    $sth->execute($resume->id, $lower, $upper);
    my $ar = $sth->fetchrow_arrayref;
    if ($$ar[0]) {
        # record this.
        $sth = $dbh->prepare("insert into praux_metrics (resume, instance, metric_alias, lower_bound, upper_bound, data, label) " . 
            "values (?,?,?,?,?,?,?)");
        $sth->execute($resume->id, $resume->instance, 'resume-user_activity', $lower, $upper, $$ar[0], 'Resume Edits / Updates');
    }

}

sub process_visits_by_content_type {
    my ($resume, $lower, $upper, $content_types) = @_;

    foreach my $ct (@$content_types) {
        my $sth = $dbh->prepare("select count(id) from praux_hitlog where resume = ? and create_time between ? and ? and content_type = ?");
        $sth->execute($resume->id, $lower, $upper, $ct);
        my $ar = $sth->fetchrow_arrayref;

        if ($$ar[0]) {
            # record this.
            $sth = $dbh->prepare("insert into praux_metrics (resume, instance, metric_alias, lower_bound, upper_bound, data, label) " . 
                "values (?,?,?,?,?,?,?)");
            $sth->execute($resume->id, $resume->instance, 'resume-web_visits_content_type', $lower, $upper, $$ar[0], 'Visits with Content-type "' . $ct . '"');
        }
    }
}

sub process_visits_by_views {
    my ($resume, $lower, $upper, $views) = @_;

    foreach my $view (@$views) {
        my $sth = $dbh->prepare("select count(id) from praux_hitlog where resume = ? and create_time between ? and ? and view = ?");
        $sth->execute($resume->id, $lower, $upper, $view);
        my $ar = $sth->fetchrow_arrayref;

        if ($$ar[0]) {
            # record this.
            $sth = $dbh->prepare("insert into praux_metrics (resume, instance, metric_alias, lower_bound, upper_bound, data, label) " . 
                "values (?,?,?,?,?,?,?)");
            $sth->execute($resume->id, $resume->instance, 'resume-web_visits_views', $lower, $upper, $$ar[0], 'Visits to View ' . $view);
        }
    }
}

sub process_visits_by_language {
    my ($resume, $lower, $upper, $langs) = @_;

    foreach my $lang (@$langs) {
        my $sth = $dbh->prepare("select count(id) from praux_hitlog where resume = ? and create_time between ? and ? and language = ?");
        $sth->execute($resume->id, $lower, $upper, $lang);
        my $ar = $sth->fetchrow_arrayref;

        if ($$ar[0]) {
            # record this.
            $sth = $dbh->prepare("insert into praux_metrics (resume, instance, metric_alias, lower_bound, upper_bound, data, label) " . 
                "values (?,?,?,?,?,?,?)");
            $sth->execute($resume->id, $resume->instance, 'resume-web_visits_lang', $lower, $upper, $$ar[0], 'Resume Visits in ' . $praux->lang_short_to_long_en($lang));
        }
    }
}

sub process_web_visits_by_cache {
    my ($resume, $lower, $upper) = @_;
    my $sth = $dbh->prepare("select count(id) from praux_hitlog where resume = ? and create_time between ? and ? and from_cache = 1");
    $sth->execute($resume->id, $lower, $upper);
    my $ar = $sth->fetchrow_arrayref;

    if ($$ar[0]) {
        # record this.
        $sth = $dbh->prepare("insert into praux_metrics (resume, instance, metric_alias, lower_bound, upper_bound, data, label) " . 
            "values (?,?,?,?,?,?,?)");
        $sth->execute($resume->id, $resume->instance, 'resume-web_visits_cache', $lower, $upper, $$ar[0], 'Resume Visits Served From Cache');
    }

    my $sth = $dbh->prepare("select count(id) from praux_hitlog where resume = ? and create_time between ? and ? and from_cache = 0");
    $sth->execute($resume->id, $lower, $upper);
    my $ar = $sth->fetchrow_arrayref;

    if ($$ar[0]) {
        # record this.
        $sth = $dbh->prepare("insert into praux_metrics (resume, instance, metric_alias, lower_bound, upper_bound, data, label) " . 
            "values (?,?,?,?,?,?,?)");
        $sth->execute($resume->id, $resume->instance, 'resume-web_visits_cache', $lower, $upper, $$ar[0], 'Resume Visits Not From Cache');
    }
}

sub process_web_visits_by_robot {
    my ($resume, $lower, $upper) = @_;
    my $sth = $dbh->prepare("select count(id) from praux_hitlog where resume = ? and create_time between ? and ? and is_robot = 1");
    $sth->execute($resume->id, $lower, $upper);
    my $ar = $sth->fetchrow_arrayref;

    if ($$ar[0]) {
        # record this.
        $sth = $dbh->prepare("insert into praux_metrics (resume, instance, metric_alias, lower_bound, upper_bound, data, label) " . 
            "values (?,?,?,?,?,?,?)");
        $sth->execute($resume->id, $resume->instance, 'resume-web_visits_robots', $lower, $upper, $$ar[0], 'Resume Visits By Robots / Crawlers');
    }

    my $sth = $dbh->prepare("select count(id) from praux_hitlog where resume = ? and create_time between ? and ? and is_robot = 0");
    $sth->execute($resume->id, $lower, $upper);
    my $ar = $sth->fetchrow_arrayref;

    if ($$ar[0]) {
        # record this.
        $sth = $dbh->prepare("insert into praux_metrics (resume, instance, metric_alias, lower_bound, upper_bound, data, label) " . 
            "values (?,?,?,?,?,?,?)");
        $sth->execute($resume->id, $resume->instance, 'resume-web_visits_robots', $lower, $upper, $$ar[0], 'Resume Visits By Humans');
    }
}


sub process_web_visits {
    my ($resume, $lower, $upper) = @_;
    my $sth = $dbh->prepare("select count(id) from praux_hitlog where resume = ? and create_time between ? and ?");
    $sth->execute($resume->id, $lower, $upper);
    my $ar = $sth->fetchrow_arrayref;

    if ($$ar[0]) {
        # record this
        $sth = $dbh->prepare("insert into praux_metrics (resume, instance, metric_alias, lower_bound, upper_bound, data, label) " . 
            "values (?,?,?,?,?,?,?)");
        $sth->execute($resume->id, $resume->instance, 'resume-web_visits', $lower, $upper, $$ar[0], 'Resume Visits (Total)');
    }
}

sub metric_exists {
    my ($name, $lower, $upper) = @_;
    my $sth = $dbh->prepare("select id from praux_metrics where metric_alias = ? AND lower_bound = ? AND upper_bound = ?");
    $sth->execute($name, $lower, $upper);
    return $sth->fetchrow_arrayref->[0];
}

