package Praux::Url::JSON::SetViews;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use JSON;

my $json = new JSON;

#
# kk .. this is a blues riff in b, watch me for the changes...
# and try to keep up. 
#

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    # if we're not logged in, do nothing
    unless ($self->active_user) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "You have to be logged in please...",
            }
        );
        return OK;
    }

    # only the owner can create content blocks.
    unless ($self->active_user->id == $self->resume->praux_user->id) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Only the owner of this resume can set views... why dont you go get them for me?",
            }
        );
        return OK;
    }
    
    my $class = shift(@uri);
    
    # initialize "our" arrayref.  we can not call ourselves, we have to take care 
    my $json_return->{$class} = [] unless $json_return->{$class};
    
    # ok we're sending home json
    my $views = $json->decode($romeo->param('views'));
    
    # annd now blocks
    if (ref($views) eq "HASH") {
        foreach my $key (keys %$views) {
            my $cb = $self->cb($key);
            next unless $cb;
            if ($cb->resume->praux_user->id != $self->active_user->id) {
                push(@{$json_return->{$class}}, {
                    error => 'Error modifying key: Access Denied',
                    success => 0,
                });
            } else {
                # update the block
                $cb->set_views(@{$views->{$key}});
                
                if ($cb->format eq "section_header") {
                    # get the section
                    my $sec = $cb->section;

                    # now update that.
                    $sec->set_views(@{$views->{$key}});
                    push(@{$json_return->{$class}}, {
                        success => 1,
                        block => $key,
                        section => $sec->id,
                    });
                } else {
                    push(@{$json_return->{$class}}, {
                        success => 1,
                        block => $key,
                    });
                }
            }
        }
    } else {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Unexpected input received!",
            }
        );
        return OK;
    }
    
    # clear the cache for this instance
    $self->clear_all_cache;
    
    $self->log_action({
        action => $class,
        resume => $self->resume,
        instance => $self->resume->instance,
        acting_user => $self->active_user->id,
    });
    
    $json_return->{general_message} = "Views updated successfully!";
    $json_return->{success} = 1;
    $romeo->r->content_type('application/x-javascript');
    print $json->encode($json_return);
    
    return OK;
}
1;
