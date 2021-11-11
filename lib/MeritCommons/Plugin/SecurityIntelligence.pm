#
# A plugin that gathers additional statistics on logins and provides hooks
# for handling accounts that appear to be compromised
#

package MeritCommons::Plugin::SecurityIntelligence;

# Plugin that implements an OAuth2 IdP and Client
our $VERSION = 0.01;

use Mojo::Base 'MeritCommons::Plugin';
use Mojo::JSON qw/encode_json decode_json/;
use MeritCommons::Config;
use MaxMind::DB::Reader::XS;
use List::Util 'sum0';

our $mmdb;

# import crypto libraries
sub _register {
    my ($plugin, $app) = @_;
    
    $app->helper('si.plugin' => sub {
        return $plugin;
    });
    
    $app->on('failed_login_attempt' => \&_handle_failed_login);
}

sub _handle_failed_login {
    my ($app, $c, $attempted_uid) = @_;
    
    #
    # unpack the goods...
    #
    my ($remote_addr, $c14n_uid);
    eval {
        $remote_addr = $c->tx->remote_address;
        $c14n_uid = lc($attempted_uid);
    };
    
    if (my $error = $@) {
        $app->log->warn("SecurityIntelligence - problem retrieving remote address: $error");
        return;
    }

    #
    # Get the stats we know MeritCommons already collects, we can use those..
    #
    
    my $ip_fail_count = $c->cache->get("$remote_addr-failed_logins");
    my $user_fail_count = $c->cache->get("$attempted_uid-failed_logins");
    
    my $ip_failed_logins_from_multiple_users = 0;
    # determine if we have had fails from more than one ID..
    if ($ip_fail_count > ($user_fail_count + 5)) {
        # this IP has had failed logins from more than one ID.
        $ip_failed_logins_from_multiple_users = 1;
    }
    
    unless (defined($mmdb)) {
        eval {
            $mmdb = MaxMind::DB::Reader::XS->new(
                file => $c->security_intelligence->plugin->asset_path . "/mmdb/GeoLite2-City.mmdb",  
            );
        };
        
        if (my $error = $@) {
            $app->log->error("error loading GeoLocation data file from '@{[$c->security_intelligence->plugin->asset_path]}" .
                             "/mmdb/GeoLite2-City.mmdb"
            );
            return;
        }
    }

    # grab the config hash    
    my $pc = $c->security_intelligence->config;

    #
    # 2 types of threats... 
    #  * ip threats (brute force detection)
    #  * geographic threats (user logged in from somewhere anomalous)
    #
    my $threat_type = 'none';

    #
    # See if this user exists or is not in the system...
    #
    if (my $user = $c->m->resultset('Model::User')->find({ userid => $c14n_uid })) {

        # if they do, pull their geographic coordinates out of cache
        my $geo_history;

        if (my $collection = $user->geo_history) {
            $geo_history = decode_json($collection->first);
        }
        
        # initialize empty histories
        $geo_history = [] unless $geo_history;
        
        my (@lat_hist, @long_hist, $lat_dev, $long_dev, $lat_mean, $long_mean, $home_deviation, $normal_deviation);
        
        # we only want the newest $pc->{coordinate_history}...
        while (scalar(@$geo_history) > ($c->pc->{coordinate_history} - 1)) {
            pop(@$geo_history);
        }
        
        foreach my $cset (@$geo_history) {
            push(@lat_hist, $cset->[0]);
            push(@long_hist, $cset->[1]);
        }

        # get the coordinates for this particular login
        my $coords = $mmdb->record_for_address($remote_addr);

        # compute standard deviation and mean...
        if (scalar(@lat_hist) + 1 >= $pc->{coordinate_history} && $pc->{geo_threat}->{stdev_threshold}) {
            $lat_dev = __stdev(@lat_hist);
            $long_dev = __stdev(@long_hist);
            
            # get rid of the oldest
            pop(@lat_hist);
            pop(@long_hist);
            
            my $this_lat_dev = __stdev(@lat_hist, $coords->{location}->{latitude});
            my $this_long_dev = __stdev(@long_hist, $coords->{location}->{longitude});
            
            # check 
            if ($this_lat_dev + $this_long_dev > ($lat_dev + $long_dev + $pc->{geo_threat}->{stdev_threshold})) {
                $threat_type = 'geo_stdev';
                $c->audit_log("$remote_addr - $c14n_uid - login caused standard deviation difference greater than " . 
                    "$pc->{geo_threat}->{stdev_threshold}, registering login attempt as 'geo_stdev' threat");
            }
        }
    
        $lat_mean = __mean(@lat_hist);
        $long_mean = __mean(@long_hist);
        
        if ($threat_type eq 'none' && $pc->{geo_threat}->{mean_threshold}) {

            my $hist_comb = $lat_mean + $long_mean;
            my $this_comb = $coords->{location}->{latitude} + $coords->{location}->{longitude};
            if (abs($this_comb) + $pc->{geo_threat}->{mean_threshold} > abs($hist_comb)) {
                $threat_type = 'geo_mean';
                $c->audit_log("$remote_addr - $c14n_uid - login had an geographical difference greater than their personal average; " . 
                    "$pc->{geo_threat}->{mean_threshold}, registering login attempt as 'geo_mean' threat");
            }   
        }
        
        if ($threat_type eq 'none' && $pc->{geo_threat}->{home_threshold}) {
            my $home = sum0(@{$pc->{home_coords}});
            my $this_comb = $coords->{location}->{latitude} + $coords->{location}->{longitude};
            if (abs($this_comb) + $pc->{geo_threat}->{homethreshold} > abs($home)) {
                $threat_type = 'geo_home';
                $c->audit_log("$remote_addr - $c14n_uid - login had an average geographical difference greater than " .  
                    "$pc->{geo_threat}->{home_threshold} from home_coords, registering login attempt as 'geo_home' threat");
            }
        }   

        # store the new login.
        $user->geo_history(encode_json([@$geo_history, [
            $coords->{location}->{latitude}, 
            $coords->{location}->{longitude}
        ]]));

    } else {
        # this isn't a user that exists in our system... but the IP might be trying to brute force
        if ($ip_fail_count > $pc->{brute_force_threshold} && $ip_failed_logins_from_multiple_users) {
            $threat_type = 'brute_force';
            $c->audit_log("$remote_addr - $c14n_uid - ip address attempted to log in to an account that " . 
                "does not exist, and has attempted to access multiple accounts, registering login attempt " .
                "as 'brute_force' threat.");
        }
    }
    
    if ($threat_type eq 'none') {
        return;
    } else {
        $c->handle_threat($threat_type);
    }
}
    
sub __mean {
    return scalar(@_) ? sum0(@_) / scalar(@_) : 0;
}

sub __stdev {
    return 0 unless scalar(@_) > 1;

    my $avg;
    unless ($avg = __mean(@_)) {
        return 0;
    }

    my $t;
    for (@_) {
        $t += ($avg - $_) ** 2;
    }

    return( ($t / scalar(@_) - 1) ** 0.5 );
}

1;