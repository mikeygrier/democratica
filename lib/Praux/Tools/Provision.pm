package Praux::Tools::Provision;

@ISA = ('Praux::Url::Component');

use WWW::Romeo;
use WWW::Romeo::Extension;
use Praux::Url::Component;
use Apache2::Upload;
use Apache2::Const qw/:common/;
use Apache2::Util qw /ht_time/;
use Digest::MD5 qw/md5_hex/;

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    
    my $to_serialize = {
        success => 1,
    };
    
    # make sure this ip is valid... on the guest list
    my $valid_ip;
    foreach my $ip (@{$romeo->c->PROVISION_IPS}) {
        if ($ip eq $romeo->r->connection->remote_ip) {
            $valid_ip = 1;
        }
    }
    
    unless ($valid_ip) {
        return {
            success => 0,
            error => "You're not on the guest list!",
        }
    }
    
    # authenticate the provisioner (by seeing if we can find one!)
    my $provisioner = $self->provisioner_by_hash($romeo->param('provision_hash'));
    unless ($provisioner && $provisioner->provision_key eq $romeo->param('provision_key')) {
        return {
            success => 0,
            error => 'Invalid provisioner credentials!',
        }
    }
    
    # files!
    my ($resume_template) = $romeo->{apr}->upload('resume_template');
    my ($install_theme) = $romeo->{apr}->upload('install_theme');
    my ($theme_name) = $romeo->param('theme_name');
    
    # provisioning defaults!
    my $create_resume = $romeo->param('create_resume');
    my $default_language = $romeo->param('default_language');
    my $default_theme = $romeo->param('default_theme');
    my $verify_email = $romeo->param('verify_email');
    
    # account information
    my $user_cn = $romeo->param('user_cn');
    my $user_email = $romeo->param('user_email');
    my $user_password = $romeo->param('user_password');
    my $referrer = $romeo->param('referrer');
    my $external_id = $romeo->param('external_id');
    my $external_type = $romeo->param('external_type');
    
    # resume information
    my $resume_address = $romeo->param('resume_address');
    my $resume_email = $romeo->param('resume_email');
    my $resume_phone = $romeo->param('resume_phone');
    my $resume_name = $romeo->param('resume_name');
    my $resume_instance = $romeo->param('resume_instance');
    
    # set defaults..
    if ($provisioner->force_defaults) {
        $create_resume = $provisioner->create_resume;
        $verify_email = $provisioner->verify_email;
        $default_theme = $provisioner->default('theme');
        $install_theme = $provisioner->default('install_theme');
        $resume_template = $provisioner->default('resume_template');
        $default_language = $provisioner->default('language');
    } else {
        # supplement the values if they're not there..
        unless (defined $default_theme) {
            $default_theme = $self->global_theme_by_name($provisioner->default('theme'));
        }
        unless (defined $install_theme) {
            $install_theme = $provisioner->default('install_theme');
        }
        unless (defined $resume_template) {
            $resume_template = $provisioner->default('resume_template');
        }
        unless (defined $create_resume) {
            $create_resume = $provisioner->create_resume;
        }
        unless (defined $verify_email) {
            $verify_email = $provisioner->verify_email;
        }
        unless (defined $default_language) {
            $default_language = $provisioner->default('language');
        }
    }
    
    # ok, at this point we should have everything we need.. let's see if we have enough info to do this successfully..
    unless ($user_cn && $user_email && $user_password) {
        return {
            success => 0,
            error => 'Not enough information to create user! (Required: user_cn, user_email, and user_password)',
        }
    }
    
    if ($self->user_by_email($user_email)) {
        return {
            success => 0,
            error => "A user with the email address '$user_email' already exists!"
        }
    }
    
    if ($create_resume) {
        # do we have enough info?
        unless ($resume_instance && $resume_name && $resume_email) {
            return {
                success => 0,
                error => 'Not enough information to create resume! (Required: resume_instance, resume_name, and resume_email)',
            }
        }
        
        # does this resume already exist?
        if ($self->resume_by_instance($resume_instance)) {
            return {
                success => 0,
                error => "A resume with the name '$resume_instance' already exists!",
            }
        }
    }
    
    # ok at this point we have all our info, we've inserted defaults, we've checked for dupes..  let's actually try and do it!
    
    # first make the user
    my $user_attrs = {
        provisioner => $provisioner->id,
        email => $user_email,
        password => $user_password,
        common_name => $user_cn,
        referrer => $referrer,
        external_id => $external_id,
        external_type => $external_type,
    };
    
    if ($verify_email) {
        $user_attrs->{verify_token} = _rand_md5hex($user_email);
    } else {
        $user_attrs->{verify_token} = "VERIFIED";
        $user_attrs->{verified} = 1;
    }
    
    # create the user..
    my $user;
    eval {
        $user = $self->schema->resultset('User')->create($user_attrs);
    };
    
    if (my $error = $@) {
        return {
            success => 0,
            error => "Error creating user: $error",
        }
    } else {
        $to_serialize->{user_provision}->{message} = "User '$user_email' provisioned successfully!";
        $to_serialize->{user_provision}->{time} = $user->create_time;
        $to_serialize->{user_provision}->{success} = 1;
        $to_serialize->{user_provision}->{id} = $user->id;
    }
    
    # ok .. no errors yet, but now we have to return $to_serialize because we have user data in there.. 
    if ($create_resume) {
        my $resume;
        eval {
            $resume = $self->schema->resultset('Resume')->create(
                {
                    name => $resume_name,
                    email => $resume_email,
                    phone => $resume_phone,
                    address => $resume_address,
                    default_language => $default_language,
                    instance => $resume_instance,
                    praux_user => $user->id,
                }
            );
        };
        if (my $error = $@) {
            $to_serialize->{resume_provision}->{success} = 0;
            $to_serialize->{resume_provision}->{error} = "Resume '$resume_instance' failed to provision: $error";
        } else {
            $to_serialize->{resume_provision}->{success} = 1;
            $to_serialize->{resume_provision}->{message} = "Resume '$resume_instance' successfully provisioned!";
            if ($resume && $install_theme && $default_theme) {
                # we're installing the theme as the value of default_theme
                my $theme_uuid = $self->new_uuid;
                my $theme_deploy_dir = $romeo->c->PRAUX_THEME_DIR . "/" . $theme_uuid . "/";
                my $theme_temp_file = "/tmp/" . $theme_uuid . ".zip";

                open(TEMPFILE, '>', $theme_temp_file) or die "Error opening temp file '$theme_temp_file': $!\n";
                my $fh = $install_theme->fh();
                while (my $td = <$fh>) {
                    print TEMPFILE $td;
                }
                close(TEMPFILE);

                system("/usr/bin/unzip -qq $theme_temp_file -d $theme_deploy_dir");

                my $data = {
                    deploy_uuid => $theme_uuid,
                    theme_name => $default_theme,
                    owner => $user->id,
                    resume => $resume->id,
                    deploy_type => 'local',
                };

                my $rs = $self->schema->resultset('Resume::Theme')->search(
                    {
                        theme_name => $theme_name,
                        owner => $user->id,
                        resume => $resume->id,
                    }
                );

                if ($rs->count > 0) {
                    foreach my $theme ($rs->all) {
                        # get rid of the old dir...
                        if ($theme->deploy_uuid && -d $romeo->c->PRAUX_THEME_DIR . "/" . $theme->deploy_uuid . "/") {
                            system("/bin/rm -r " . $romeo->c->PRAUX_THEME_DIR . "/" . $theme->deploy_uuid . "/");
                            $theme->delete;
                        }
                    }
                }
            
                my $theme = $self->schema->resultset('Resume::Theme')->create($data);
                $to_serialize->{resume_provision}->{theme_message} = "Theme added as '$theme_name'";
                
                # set this as the resume's default theme!
                $resume->default_theme($theme->id);
                $resume->update;
            } elsif (ref($default_theme)) {
                # use this global theme!
                $resume->default_theme($default_theme->id);
                $resume->update;
            }
            if ($resume && $resume_template) {
                my $yaml;
                
                if (ref($resume_template) && $resume_template->can('fh')) {                    
                    my $fh = $resume_template->fh();
                    {
                        local $/;
                        $yaml = <$fh>;
                    }
                } else {
                    $yaml = $resume_template;
                }
                
                eval {
                    $self->import_yaml_resume($yaml, $resume->instance);
                };
                if (my $error = $@) {
                    $to_serialize->{resume_provision}->{install_template_message} = "Error installing YAML resume template: $error";
                } else {
                    $to_serialize->{resume_provision}->{install_template_message} = "YAML resume template installed successfully!";
                }
            }
            
            $self->log_action({
                action => __PACKAGE__,
                resume => $resume->id,
                instance => $resume->instance,
                acting_user => $user->id,
            });
        }
    }
    
    $to_serialize->{time_taken} = $romeo->time_taken;
    
    return $to_serialize;
}

sub _rand_md5hex {
    my ($password) = @_;
    $password = substr($_[0], sprintf('%d', rand(length($password))), 4) if ($_[0]);
    my ($r1, $r2, $r3, $r4);
    $r1 = sprintf('%d2', rand(100));
    $r2 = rand($r1);
    $r3 = sprintf('%d2', rand(122580 + $r2));
    $r4 = rand($r3 + $r2);
    return md5_hex("$r1$r2$r3$password$r4");
}

1;
