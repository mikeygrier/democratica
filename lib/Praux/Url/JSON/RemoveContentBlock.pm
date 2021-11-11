package Praux::Url::JSON::RemoveContentBlock;

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

    # ok we only NEED one field.. lets just do something more sane then that array crap
    unless ($romeo->param_was_sent('content_block') || $romeo->param_was_sent('content_item')) {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "Must specify either content_block or content_item in edit_content_item request.",
            }
        );
        return OK;
    }

    my (@blocks) = $romeo->param('content_block');
    
    # do. want.
    my $class = shift(@uri);
    
    # keep track of the goodies.
    my $json_return = $romeo->param('json_return') || {};
    $json_return->{$class} = [] unless $json_return->{$class};
    $json_return->{removed_blocks} = [];
    
    if (scalar(@blocks) > 0) {
        foreach my $blockid (@blocks) {
            
            my $cb = $self->cb($blockid);

      		unless ($cb) {
				push(@{$json_return->{$class}}, {
                    message => "Error removing content block: content block not found!",
                });
			}
      
            unless ($self->active_user->id == $cb->resume->praux_user->id) {
                push(@{$json_return->{$class}}, {
                    message => "Error removing content block $blockid: Access Denied",
                });
                next;
            }
			
			# take section headers into account.
            if ($cb->format eq "section_header") {
				# just be informative
				push(@{$json_return->{$class}}, {
                    message => "Also deleting section #" . $cb->section->id,
                });
	
				# delete the section, the block will cascade.
				eval {
					$cb->section->delete();
				};
			} else {
				# delete just the block
	            eval {
	                $cb->delete();
	            };
			}
            
            $self->log_action({
                section => $cb->section->id,
                content_block => $cb->id,
                action => $class,
                resume => $cb->resume->id,
                instance => $cb->resume->instance,
                acting_user => $self->active_user->id,
            });
          
            if (my $error = $@) {
                push(@{$json_return->{$class}}, {
                    message => "Error removing content block #$blockid: $@",
                });
            } else {
                push(@{$json_return->{$class}}, {
                    message => "Successfully removed content block #$blockid.",
                });
                push(@{$json_return->{removed_blocks}}, $blockid);
            }
        }
        
        # clear the cache for this instance
        $self->clear_all_cache;
        
        $json_return->{success} = 1;
        $json_return->{general_message} = "Content block(s) successfully removed! note: (" . join(', ', map { $_->{message} } @{$json_return->{$class}}) . ")";
        
        $romeo->r->content_type('application/x-javascript');
        print $json->encode($json_return);
        return OK;
    } else {
        $romeo->r->content_type('application/x-javascript');
        print $json->encode(
            {
                success => 0,
                error => "No content block(s) specified.",
            }
        );
    }

}
1;
