#    MeritCommons Portal
#    Copyright 2013 Wayne State University
#    All Rights Reserved

package MeritCommons::Plugin::SAML2::Command::saml2;

use Mojo::Base 'Mojolicious::Command';
use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Crypt::Digest qw/digest_data_hex digest_file/;
use List::MoreUtils qw/distinct/;
use Crypt::X509;
use Mojo::UserAgent;
use Mojo::Util qw/b64_decode/;
use Mojo::DOM;
use Mojo::File;
use JSON::XS;
use Struct::Compare;

has description => "Management Interface for the SAML2 plugin\n";
has subcommands => sub {
    [
        [qw/service_provider list_federations refresh_metadata/],
    ];
};

sub run {
    my ($self, @args) = @_;

    # extract sub command
    my ($sc) = shift @args;

    if ($sc) {
        if ($self->can("c_$sc")) {
            my $method = "c_$sc";
            return $self->$method(@args);
        }
        print "[error] unknown command '$sc'\n";
    } else {
        print $self->usage;
    }
}

sub c_list_federations {
    my ($self, @args) = @_;

    foreach my $fed (@{$self->app->saml2->all_federations}) {
        print "$fed->{entity_id} ($fed->{metadata_id})\n";
    }
}

sub c_refresh_metadata {
    my ($self, @args) = @_;
    $self->app->saml2->render_metadata;
    print "[info] refreshed metadata file @{[$self->app->saml2->plugin->plugin_data_dir]}/metadata.xml\n";
    print "       it should be immediately available at @{[$self->app->config->{front_door_url}]}/saml2/metadata.xml\n";
}

sub c_service_provider {
    my ($self, @args) = @_;

    # extract operation
    my ($op) = shift @args;

    GetOptionsFromArray(
        \@args,
        'i|entity-id=s' => \my $entity_id,
        'c|consumer-url=s' => \my @ac_urls,
        'r|requested-attribute=s' => \my @requested_attributes,
        'm|metadata-id=s' => \my $metadata_id,
        's|signing-key=s' => \my @signing_keys,
        'e|encryption-key=s' => \my @encryption_keys,
        'k|general-keys=s' => \my @general_keys,
        'x|metadata-url=s' => \my $metadata_url,
        'n|name-id-format=s' => \my $name_id_format,
        'o|name-id-attribute=s' => \my $name_id_attribute,
        'q|name-qualifier=s' => \my $name_qualifier,
        'a|audience=s' => \my @audiences,
        't|terminate-session' => \my $terminate_session,
        'w|wants-assertions-signed' => \my $wants_assertions_signed,
        'g|authn-requests-signed' => \my $authn_requests_signed,
        'after-logout-url' => \my $after_logout_url,
        'skip-signature-check' => \my $skip_signature_check,
        'entity-attributes' => \my @entity_attributes,
        'b|include-attr-bundle' => \my $include_attr_bundle,
    );

    my $app = $self->app;

    # default NameIDFormat to 'unspecified' if it was, well, unspecified
    $name_id_format = 'urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified' unless $name_id_format;

    # default MeritCommons User attribute to use for NameID (email or userid, based on format)
    unless ($name_id_attribute) {
        if ($name_id_format eq 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress') {
            $name_id_attribute = 'email_address';
        } else {
            $name_id_attribute = 'userid';
        }
    }

    if ($metadata_url) {
        my $default_name_id_format = $name_id_format;
        my @default_ac_urls = @ac_urls;
        my @default_audiences = @audiences;
        my @default_requested_attributes = @requested_attributes;
    
        my $md;
        if ($metadata_url =~ /^http/) {
            # we can autoconfig...
            my $ua = Mojo::UserAgent->new();
            $md = $ua->get($metadata_url)->res->body;
            print "[saml2] using source: Mojo::UserAgent\n" if $ENV{MERITCOMMONS_DEBUG};
        } elsif ($metadata_url =~ qr{^file://(/+)$} && -e $1) {
            $md = Mojo::File->new($1)->slurp;
            print "[saml2] uising source: Local File URL\n" if $ENV{MERITCOMMONS_DEBUG};
        } elsif (-e $metadata_url) {
            $md = Mojo::File->new($metadata_url)->slurp;
            print "[saml2] uising source: Local File Path\n" if $ENV{MERITCOMMONS_DEBUG};
            print "[warning] '$metadata_url' isn't a URL, it's a local path.  Attempting to do what you mean...\n";
        }

        print "[saml2] retrieved " . length($md) . " bytes of data from $metadata_url\n" if $ENV{MERITCOMMONS_DEBUG};

        my $doc;
        # avoid parsing large xml documents twice!
        eval {
            $doc = Mojo::DOM->new->xml(1)->parse($md);
        };
        
        if (my $error = $@) {
            die "[fatal] error parsing XML in $metadata_url: $error\n";
        }
        
        print "[saml2] parsed DOM of $metadata_url\n" if $ENV{MERITCOMMONS_DEBUG};
        if ($skip_signature_check || $app->saml2->verify_signed_xml($doc, 1, 1)) {
            my $count;
            foreach my $ed ($doc->find('EntityDescriptor')->each) {
                unless ($ed->at('SPSSODescriptor')) {
                    print "[info] skipping EntityID $entity_id, no SPSSODescriptor found!\n";
                    next;
                }                

                #
                # Get federation data out of the SPSSODescriptor, specifically AuthnRequestsSigned
                # and WantAssertionsSigned
                #
                my $spd = $ed->at('SPSSODescriptor');
                if (my $ars_text = $spd->attr('AuthnRequestsSigned')) {
                    if ($ars_text =~ /^true$/i) {
                        $authn_requests_signed = 1;
                    }
                }

                # spec dictates this default to 'false', so unless it was true... it's false
                $authn_requests_signed = 0 unless $authn_requests_signed;

                if (my $was_text = $spd->attr('WantAssertionsSigned')) {
                    if ($was_text =~ /^true$/i) {
                        $wants_assertions_signed = 1;
                    }
                }
                
                # spec dictates this default to 'false', so unless it was true... it's false
                $wants_assertions_signed = 0 unless $wants_assertions_signed;

                # reset these to what was passed in as we'll get them from the metadata
                @ac_urls = @default_ac_urls;
                @audiences = @default_audiences;
                $name_id_format = $default_name_id_format;
                @requested_attributes = @default_requested_attributes;

                my $entity_id = $ed->attr('entityID');
                my $metadata_id = $ed->attr('ID');
                
                # damn their default, we're using HTTP-POST.
                $ed->find('AssertionConsumerService[Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"]')->each(sub {
                    push(@ac_urls, $_->{Location});
                });

                my $ni = $ed->find('NameIDFormat')->first;
                if ($ni) {
                    $name_id_format = $ni->text;
                }

                @encryption_keys = (distinct(
                    @encryption_keys,
                    map { join('', split(/\s+/, $_->text)) } @{$ed->find('SPSSODescriptor [use="encryption"] X509Certificate')}
                ));
                @signing_keys = (distinct(
                    @signing_keys,
                    map { join('', split(/\s+/, $_->text)) } @{$ed->find('SPSSODescriptor [use="signing"] X509Certificate')}
                ));
                @general_keys = (distinct(
                    @general_keys,
                    map { join('', split(/\s+/, $_->text)) } @{$ed->find('SPSSODescriptor X509Certificate')}
                ));

                my $thumbprint;
                if (scalar(@signing_keys)) {
                    $thumbprint = $app->thumbprint(b64_decode($signing_keys[0]));
                } elsif (scalar(@general_keys)) {
                    $thumbprint = $app->thumbprint(b64_decode($general_keys[0]));
                } elsif (scalar(@encryption_keys)) {
                    $thumbprint = $app->thumbprint(b64_decode($encryption_keys[0]))
                }

                unless ($thumbprint) {
                    die "Metadata has no usable key for thumbprint, please specify a signing key (see --help for more info).\n";
                }

                # if we found a key not specified for a particular use, use it for both things.
                unless (scalar(@encryption_keys)) {
                    if (scalar(@general_keys)) {
                        @encryption_keys = @general_keys;
                    }
                }

                unless (scalar(@signing_keys)) {
                    if (scalar(@general_keys)) {
                        @signing_keys = @general_keys;
                    }
                }

                # the entity ID is the default audience
                unless (scalar(@audiences)) {
                    @audiences = ($entity_id);
                }

                # only keep track of Name
                @requested_attributes = distinct(
                    @requested_attributes,
                    @{$ed->find('AttributeConsumingService RequestedAttribute')->map(attr => 'Name')}
                );

                foreach my $eattr (@{$ed->find('EntityAttributes')}) {
                    push(@entity_attributes, {
                         name => $eattr->attr('Name'), 
                         values => [ map { $_->text } $eattr->find("AttributeValue") ],
                    });
                }

                add_or_modify_service_provider($app, {
                    entity_id => $entity_id,
                    thumbprint => $thumbprint,
                    assertion_consumer_url => \@ac_urls,
                    metadata_id => ($metadata_id // $app->new_uuid),
                    name_id_format => $name_id_format,
                    name_id_attribute => $name_id_attribute,
                    name_qualifier => $name_qualifier,
                    audiences => \@audiences,
                    requested_attributes => \@requested_attributes,
                    logout_destroys_meritcommons_session => $terminate_session ? 1 : 0,
                    after_logout_url => $after_logout_url,
                    wants_assertions_signed => $wants_assertions_signed,
                    authn_requests_signed => $authn_requests_signed,
                    entity_attributes => \@entity_attributes,
                    entity_certificates => {
                        signing => \@signing_keys,
                        encryption => \@encryption_keys,
                    }
                });
                $count++;
            }
            if ($count) {
                print "[info] added or updated $count trust relationship(s) from $metadata_url\n";
            } else {
                print "[error] couldn't find any EntityDescriptors with SPSSODescriptor definitions in $metadata_url\n";
            }
            exit;
        } else {
            die "[fatal] invalid or unsupported signature on $metadata_url (see --help for more info)\n";       
        }
    }

    if ($entity_id) {
        my $rs = $app->saml2->fa_rs;
        my $ce = $rs->find({entity_id => $entity_id});
        
        # the entity ID is the default audience
        unless (scalar(@audiences)) {
            @audiences = ($entity_id);
        }

        my $md_changed;
        if (lc($op) eq "edit") {
            my $edit_file = Mojo::File->tempfile;
            my $jxs = JSON::XS->new->ascii->pretty->allow_nonref;
            my $orig_agreement = $ce->agreement;
            my $encoded_agreement = $jxs->encode($orig_agreement);
            $edit_file->spurt($encoded_agreement);
            
            if ($ENV{EDITOR} && -e $ENV{EDITOR}) {
                system("$ENV{EDITOR}", $edit_file->realpath->to_string);
            } elsif (-e "/usr/bin/vi") {
                system("/usr/bin/vi", $edit_file->realpath->to_string);
            } else {
                die "[fatal] no \$EDITOR defined; and /usr/bin/vi does not exist.  Please set \$EDITOR to continue\n";
            }

            my $edited_agreement = $edit_file->slurp;
            
            if ($encoded_agreement ne $edited_agreement) {
                my $new_agreement;
                eval {
                    $new_agreement = $jxs->decode($edited_agreement);
                };
                if (my $error = $@) {
                    die "[fatal] error editing agreement for @{[$ce->entity_id]}: $error\n";
                }
                
                if (scalar(@{$new_agreement->{signing}})) {
                    $new_agreement->{thumbprint} = $app->thumbprint(b64_decode($new_agreement->{signing}->[0]));
                } elsif (scalar(@{$new_agreement->{encryption}})) {
                    $new_agreement->{thumbprint} = $app->thumbprint(b64_decode($new_agreement->{encryption}->[0]))
                }
                
                _update_changed($app, $ce, $new_agreement);
                
                $md_changed = 1;
            }
		} elsif (lc($op) eq "add" || lc($op) eq "modify") {
            my $thumbprint;
            if (scalar(@signing_keys)) {
                $thumbprint = $app->thumbprint(b64_decode($signing_keys[0]));
            } elsif (scalar(@general_keys)) {
                $thumbprint = $app->thumbprint(b64_decode($general_keys[0]));
            } elsif (scalar(@encryption_keys)) {
                $thumbprint = $app->thumbprint(b64_decode($encryption_keys[0]))
            }
            
            add_or_modify_service_provider($app, {
                entity_id => $entity_id,
                thumbprint => $thumbprint,
                assertion_consumer_url => \@ac_urls,
                metadata_id => ($metadata_id // $app->new_uuid),
                name_id_format => $name_id_format,
                name_id_attribute => $name_id_attribute,
                name_qualifier => $name_qualifier,
                audiences => \@audiences,
                requested_attributes => \@requested_attributes,
                logout_destroys_meritcommons_session => $terminate_session ? 1 : 0,
                wants_assertions_signed => $wants_assertions_signed,
                authn_requests_signed => $authn_requests_signed,
                entity_certificates => {
                    signing => \@signing_keys,
                    encryption => \@encryption_keys,
                }
            });
                        
        } elsif (lc($op) eq "delete" && $entity_id) {
            eval {
                $app->saml2->fa_rs->find({entity_id => $entity_id})->delete;
            };
            
            if (my $error = $@) {
                die "[fatal] couldn't delete federation agreement for $entity_id: $error\n";
            } else {
                print "[info] service provider trust for $entity_id removed\n";
            }
        } else {
            print $self->usage('service_provider');
        }
    } else {
        print $self->usage('service_provider');
    }
}

sub add_or_modify_service_provider {
    my ($app, $hr) = @_;

    my $rs = $app->saml2->fa_rs;
    my $pc = $app->plugin_configs->saml2;
    my $ce = $rs->find({entity_id => $hr->{entity_id}});
    
    if (ref $pc eq "HASH") {
        if ($pc->{requested_attributes_strategy} eq "merge" || !$pc->{requested_attributes_strategy}) {
            if (ref $ce eq "HASH" && ref $ce->{requested_attributes} eq "ARRAY" && scalar(@{$ce->{requested_attributes}})) {
                if (ref $hr->{requested_attributes} eq "ARRAY") {
                    # let's merge using a hashref...
                    my $merged = {};

                    foreach my $attr (@{$ce->{requested_attributes}}, @{$hr->{requested_attributes}}) {
                        $merged->{$attr} = 1;
                    }

                    # merge of the two arrays of requested attributes
                    $hr->{requested_attributes} = [keys %$merged];
                } else {
                    # no requested attributes in the incoming federation config, use the ones we have on file
                    $hr->{requested_attributes} = $ce->{requested_attributes};
                }   
            }
        } elsif (!$pc->{requested_attributes_strategy} eq "overwrite") {
            die "[fatal] illegal value for requested_attributes strategy in saml2.conf: '$pc->{requested_attributes_strategy}' must be 'merge' or 'overwrite'\n";
        }
    } else {
        warn "[warning] running SAML2 plugin unconfigured is not advised, assuming defaults\n";
    }
    
    if ($ce) {
        _update_changed($app, $ce, $hr);
    } else {
        my $to_create = {
            thumbprint => $hr->{thumbprint},
            entity_id => $hr->{entity_id},
            agreement => $hr->{agreement},    
        };
        
        my @signing_key_history;
        if (exists $hr->{entity_certificates}->{signing} && ref $hr->{entity_certificates}->{signing} eq "ARRAY") {
            foreach my $cert (@{$hr->{entity_certificates}->{signing}}) {
                push(@signing_key_history, {
                    added_time => time,
                    thumbprint => $app->thumbprint($cert),
                    certificate => $cert, 
                });
            }
            $to_create->{signing_key_history} = \@signing_key_history;
        }
        
        my @encryption_key_history;
        if (exists $hr->{entity_certificates}->{encryption} && ref $hr->{entity_certificates}->{encryption} eq "ARRAY") {
            foreach my $cert (@{$hr->{entity_certificates}->{encryption}}) {
                push(@signing_key_history, {
                    added_time => time,
                    thumbprint => $app->thumbprint($cert),
                    certificate => $cert, 
                });
            }
            $to_create->{encryption_key_history} = \@encryption_key_history;
        }
        
        $ce = $rs->create($to_create);
        print "[info] new service provider trust added for $hr->{entity_id}\n";
    }
    
}

sub _update_changed {
    my ($app, $ce, $hr) = @_;
    foreach my $col_attr (qw/thumbprint entity_id metadata_id/) {
        if ($hr->{$col_attr} ne $ce->$col_attr) {
            $ce->$col_attr($hr->{$col_attr});
        }
    }
    
    unless (compare($hr, $ce->agreement)) {
        my $ce_hr = $ce->agreement;
        # update key histories, mark old keys as retired...
        my (@in_service, @to_retire);
        if (exists $hr->{entity_certificates}->{signing} && ref $hr->{entity_certificates}->{signing} eq "ARRAY") {
            foreach my $cert (@{$hr->{entity_certificates}->{signing}}) {
                # make sure this is accounted for in our current history..
                foreach my $record ($ce->signing_key_history) {
                    if ($record->{thumbprint} eq $app->thumbprint($cert)) {
                        
                    }
                }
            }
        }
        
        
        $ce->agreement($hr);
        $ce->update;
        print "[info] updated service provider trust for $hr->{entity_id}\n";
    }
    
}

sub usage {
    my ($self, @args) = @_;

    my $subcommand;
    unless ($subcommand = $args[0]) {
        $subcommand = $ARGV[1];
    }

    # empty string avoids 'undefined' errors
    $subcommand = '' unless $subcommand;

    if ($subcommand eq "service_provider") {
        return <<"EOF";
Usage: meritcommons saml2 service_provider [OPERATION] [OPTIONS]

These operations are available for 'saml2 service_provider':
        add                 Add a new federation
        modify              Modify an existing federation
        delete              Delete an existing federation
        edit                Edit an existing federation

These options are available for 'saml2 service_provider':
    -i, --entity-id                 The entity_id of the remote system to federate with, usually
                                    a url.  This is required.
    -m, --metadata-id               A unque id (usually GUID or UUID) identifying the metadata that
                                    this configuration represents.  Defaults to a random UUID.
    -c, --consumer-url              The URL in the remote system that consumes SAML2 assertions.
    -s, --signing-key               A base64 encoded x509 certificate (no newlines) to use to verify 
                                    documents and assertions signed by this remote system.  May be
                                    specified multiple times for multiple keys.
    -e, --encryption-key            A base64 encoded x509 certificate (no newlines) to use to decrypt 
                                    documents and assertions encrypted by this remote system.  May be
                                    specified multiple times for multiple keys.
    -x, --metadata-url              The URL of this Service Provider's metadata.xml file
    -n, --name-id-format            The NameID Format to use with assertions to this remote system
    -o, --name-id-attribute         Regardless of what name_id_format says, always pass this MeritCommons 
                                    User attribute as the NameID (useful for unspecified)
    -q, --name-qualifier            Security domain string to use in the SPNameQualifier attribute of 
                                    the NameID element, if not specified, no SPNameQualifier will be 
                                    passed
    -r, --requested-attribute       Specified default attribute(s) to include in assertions to this SP 
                                    in SAMLResponses.  If Metadata already provides a set of attributes, 
                                    then attributes specified here will be merged with those.
    -a, --audience                  The audience that SAML assertions will be restricted to by default.
                                    May be specified multiple times for multiple audiences.
    -t, --terminate-session         Configures this specific federation agreement to terminate any 
                                    MeritCommons session that may exist for the user upon receipt of a
                                    LogoutRequest from this Service Provider.  Note: this option will
                                    override any global settings specified in saml2.conf
    -w, --wants-assertions-signed   If true, the Service Provider wants and expects all of our assertions 
                                    to be signed with our private key.
    -g, --authn-requests-signed     If true, we should always expect the Service Provider to send only
                                    AuthnRequests that are signed with their private key.
    -b, --include-attr-bundle       Include, by default, an attribute bundle for this federation agreement
                                    currently supported values for this field are research-and-scholarship
                                    and research-and-scholarship-minimal
    --entity-attributes             Manually specify what attributes this entity has e.g. entitity-category
                                    format k=v1,v2,v3.  Please url-encode commas in values.  Specify 
                                    multiple times for multiple attributes.
    --skip-signature-check          Don't bother checking the metadata for a signature.  This vendor is
                                    slumming it.

EOF
    } else {
        return <<"EOF";
Usage: meritcommons saml2 [COMMAND] [OPTIONS]

The following commands are available for 'saml2':
        service_provider    Manage service provider agreements
        list_federations    List configured service provider agreements (takes no arguments)
        refresh_metadata    Refresh MeritCommons's metadata.xml with new values (takes no arguments)

EOF
    }
}

sub __fingerprint {
    my ($der) = @_;
    my $digest = digest_data_hex('SHA1', $der);
    return uc(join(':', ($digest =~ /.{2}/gs)));
}

1;