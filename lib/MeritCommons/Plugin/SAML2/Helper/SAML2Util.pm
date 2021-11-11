#
# Util class for SAML2
#

package MeritCommons::Plugin::SAML2::Helper::SAML2Util;

use Time::Piece;
use Time::HiRes;
use XML::CanonicalizeXML;
use Mojo::DOM;
use Mojo::URL;
use Mojo::Util qw/trim encode b64_encode b64_decode/;
use Mojo::Base 'MeritCommons::Plugin';
use Mojo::ByteStream qw/b/;
use Compress::Raw::Zlib;
use List::MoreUtils qw/uniq/;
use Mojo::File;

# no openssl, avoid segfaults because of SSLeay
use Crypt::X509;
use Crypt::PK::RSA;
use Crypt::Digest qw/digest_data/;

my $attr_bundles = {
    'research-and-scholarship' => [
        'urn:oid:1.3.6.1.4.1.5923.1.1.1.6',
        'urn:oid:1.3.6.1.4.1.5923.1.1.1.10',
        'urn:oid:0.9.2342.19200300.100.1.3',
        'urn:oid:2.16.840.1.113730.3.1.241',
        'urn:oid:2.5.4.42',
        'urn:oid:2.5.4.4',
    ],
    'research-and-scholarship-minimal' => [
        'urn:oid:1.3.6.1.4.1.5923.1.1.1.6',
        'urn:oid:0.9.2342.19200300.100.1.3',
        'urn:oid:2.16.840.1.113730.3.1.241',
    ],
};

# map the oids to names of LDAP attributes
my $an_2_ldap = {
    'urn:oid:2.5.4.3' => 'cn',
    'urn:oid:2.5.4.4' => 'sn',
    'urn:oid:2.5.4.42' => 'givenName',
    'urn:oid:0.9.2342.19200300.100.1.3' => 'mail',
    'urn:oid:0.9.2342.19200300.100.1.10' => 'manager',
    'urn:oid:2.16.840.1.113730.3.1.241' => 'displayName',
    
    # eduPerson Schema
    'urn:oid:1.3.6.1.4.1.5923.1.1.1.1' => 'eduPersonAffiliation',
    'urn:oid:1.3.6.1.4.1.5923.1.1.1.6' => 'eduPersonPrincipalName',
    'urn:oid:1.3.6.1.4.1.5923.1.1.1.7' => 'eduPersonEntitlement',
    'urn:oid:1.3.6.1.4.1.5923.1.1.1.9' => 'eduPersonScopedAffiliation',
    'urn:oid:1.3.6.1.4.1.5923.1.1.1.10' => 'eduPersonTargetedId',

    # SCHAC
    '1.3.6.1.4.1.25178.1.2.9' => 'schacHomeOrganization',

    # OSiRIS AA Schema
    'urn:oid:1.3.5.1.3.1.17128.313.1.1' => 'osirisKeyThumbprint',
    'urn:oid:1.3.5.1.3.1.17128.313.1.2' => 'osirisEntityUniqueID',
    
    # Found in PingOne's metadata, they're not ambiguous so i'll add them
    'fname' => 'givenName',
    'lname' => 'sn',
    'GetInclusiveOrgnCode' => 'Organization',
};

# map the oids to the names of MeritCommons user attributes
my $an_2_meritcommons = {
    'urn:oid:2.5.4.3' => 'common_name',
    'urn:oid:0.9.2342.19200300.100.1.3' => 'email_address',
    'emailAddress' => 'email_address',
    'email' => 'email_address',
};

# the various canonicalizations methods..
my $c14n = {
    # Exclusive Canonicalizations
    'http://www.w3.org/2001/10/xml-exc-c14n#' => sub {
        my ($xml) = @_;
        return XML::CanonicalizeXML::canonicalize(
            $xml, 
            '<XPath>/descendant-or-self::node() | //@* | //namespace::*</XPath>', '', 1, 0
        );
    },
    'http://www.w3.org/2001/10/xml-exc-c14n#WithComments' => sub {
        my ($xml) = @_;
        return XML::CanonicalizeXML::canonicalize(
            $xml, 
            '<XPath>/descendant-or-self::node() | //@* | //namespace::*</XPath>', '', 1, 1
        );
    },
    # Inclusive Canonicalizations
    'http://www.w3.org/TR/2001/REC-xml-c14n-20010315' => sub {
        my ($xml) = @_;
        return XML::CanonicalizeXML::canonicalize(
            $xml, 
            '<XPath>/descendant-or-self::node() | //@* | //namespace::*</XPath>', '', 0, 0
        );
    },
    'http://www.w3.org/TR/2001/REC-xml-c14n-20010315#WithComments' => sub {
        my ($xml) = @_;
        return XML::CanonicalizeXML::canonicalize(
            $xml, 
            '<XPath>/descendant-or-self::node() | //@* | //namespace::*</XPath>', '', 0, 1
        );
    },
};

# resolve the URLs to the algorithms used to sign and hash the XML
my $crypto = {
    # Signature: RSA-SHA256
    'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256' => {
        create => sub {
            my ($sk, $to_sign) = @_;
            return b64_encode($sk->sign_message($to_sign, 'SHA256', 'v1.5'), '');
        },
        verify => sub {
            my ($pk, $to_verify, $sig) = @_;
            if ($pk->verify_message(b64_decode($sig), $to_verify, 'SHA256', 'v1.5')) {
                return 1;
            }
            return undef;
        },
    },
    # Signature: RSA-SHA1
    'http://www.w3.org/2000/09/xmldsig#rsa-sha1' => {
        create => sub {
            my ($sk, $to_sign) = @_;
            return b64_encode($sk->sign_message($to_sign, 'SHA1', 'v1.5'), '');
        },
        verify => sub {
            my ($pk, $to_verify, $sig) = @_;
            if ($pk->verify_message(b64_decode($sig), $to_verify, 'SHA1', 'v1.5')) {
                return 1;
            }
            return undef;
        },
    },
    # Digest: SHA256
    'http://www.w3.org/2001/04/xmlenc#sha256' => sub {
        my ($to_digest) = @_;
        return b64_encode(digest_data('SHA256', $to_digest), '');
    },
    # Digest: SHA1
    'http://www.w3.org/2000/09/xmldsig#sha1' => sub {
        my ($to_digest) = @_;
        return b64_encode(digest_data('SHA1', $to_digest), '');
    },
};

sub _register {
    my ($self, $app, $saml2) = @_;

    # there's templates in the DATA!
    push @{$app->renderer->classes}, __PACKAGE__;

    # various helpers (defined below)
    $app->helper('saml2.verify_signed_xml' => \&_verify_signed_xml);
    $app->helper('saml2.timestamp' => \&_saml_timestamp);
    $app->helper('saml2.signature_for' => \&_signature_for);
    $app->helper('saml2.c14nize' => \&_c14nize);
    $app->helper('saml2.xml_sign' => \&_xml_sign);
    $app->helper('saml2.xml_verify' => \&_xml_verify);
    $app->helper('saml2.b64_digest' => \&_b64_digest);
    $app->helper('saml2.render_metadata' => \&_render_metadata);
    $app->helper('saml2.generate_artifact' => \&_generate_artifact);
    $app->helper('saml2.verify_artifact' => \&_verify_artifact);
    $app->helper('saml2.eppn_domain' => \&_eppn_domain);

    # compression (inflate/deflate) methods for HTTP-Redirect and ArtifactResolution functionality
    $app->helper('saml2.inflate' => \&_inflate);
    $app->helper('saml2.deflate' => \&_deflate);

    # actually generates the saml2 response
    $app->helper('saml2.generate_saml_response_for' => \&_generate_saml_response_for);

    # called by controllers to send saml2 responses
    $app->helper('saml2.post_response_to' => \&_post_response_to);
    $app->helper('saml2.artifact_response_to' => \&_artifact_response_to);

    # these generate XML strings for interpolation
    $app->helper('saml2.authn_statement' => \&_authn_statement);
    $app->helper('saml2.conditions_statement' => \&_conditions_statement);
    $app->helper('saml2.attribute_statement' => \&_attribute_statement);
}

sub _eppn_domain {
    my ($self) = @_;

    my $eppn_domain;
    unless ($eppn_domain = $self->stash('saml2_eppn_domain')) {
        $eppn_domain = $self->saml2->config->{eppn_domain};
        unless ($eppn_domain) {
            ($eppn_domain) = $self->config->{cookie_top_domain} =~ /^\.(.+)$/;
        }
        $self->stash('saml2_eppn_domain', $eppn_domain);
    }

    return $eppn_domain;
}

sub _generate_saml_response_for {
    my ($self, $entity_id, $user, $federation) = @_;

    my $saml_response;
    if ($user && $federation) {

        my $name_id_attribute = $federation->{name_id_attribute} // 
                                $self->saml2->config->{name_id_attribute} //
                                'userid';

        # we need at least one audience, default it to the entity_id for old configurations
        unless ((ref $federation->{audiences} eq "ARRAY") && scalar(@{$federation->{audiences}})) {
            $federation->{audiences} = [$entity_id];
        }

        my $eppn_domain = $self->saml2->eppn_domain;

        # get the user's currently scoped and unscoped affiliation(s)
        my (@affiliations, @scoped_affiliations);
        foreach my $role ($user->roles) {
            my $role_cn = $role->common_name;
            if (grep {/$role_cn/} qw/employee student faculty/) {
                push(@scoped_affiliations, "$role_cn\@$eppn_domain");
                push(@affiliations, $role_cn);
                push(@scoped_affiliations, "member\@$eppn_domain");
                push(@affiliations, 'member');
            } elsif ($role->common_name eq "alumni") {
                # eduPersonScopedAffiliation calls these 'alum'
                push(@scoped_affiliations, "alum\@$eppn_domain");
                push(@affiliations, "alum");
            }
        }
        @scoped_affiliations = sort {$a cmp $b} uniq(@scoped_affiliations);
        @affiliations = sort {$a cmp $b} uniq(@affiliations);

        unless (scalar(@scoped_affiliations)) {
            @scoped_affiliations = ("affiliate\@$eppn_domain");
        }

        unless (scalar(@affiliations)) {
            @affiliations = ("affiliate");
        }

        # if they're an employee without faculty status, add the staff status
        if (grep(/^employee/, @scoped_affiliations) && !grep(/^faculty/, @scoped_affiliations)) {
            push(@scoped_affiliations, "staff\@$eppn_domain");
            push(@affiliations, "staff");
        }

        my $e;
        if ($self->app->config->{authentication_provider} eq "MeritCommons::Helper::LDAPAuth") {
            $e = $self->user_to_ldap_entry($user);
        }
        
        
        my $include_attribute_bundle = $federation->{include_attribute_bundle} if exists $federation->{include_attribute_bundle};
        if ($include_attribute_bundle && exists $attr_bundles->{$include_attribute_bundle}) {
            my $merged_attributes = { 
                ref $federation->{requested_attributes} eq "ARRAY" ? map { $_, 1 } @{$federation->{requested_attributes}} : (),
                ref $attr_bundles->{$include_attribute_bundle} eq "ARRAY" ? map { $_, 1 } @{$attr_bundles->{$include_attribute_bundle}} : (),
            };
            
            if (scalar(keys %$merged_attributes)) {
                $federation->{requested_attributes} = [keys %$merged_attributes];
            }
        }
        
        # a container for what will make it into the assertion (if we have it)
        my $assertion_attributes = {};
        if (exists $federation->{requested_attributes} && ref $federation->{requested_attributes} eq "ARRAY") {
            # get the Net::LDAP::Entry for this object first if we are so configured.
            foreach my $oid (@{$federation->{requested_attributes}}) {
                # quick format check, for audit log purposes
                unless ($oid =~ /^urn:oid:\d/) {
                    $self->app->log->warn("SAML2 - Federation agreement with EntityID $federation->{entity_id} contains AttributeRequest with 'Name' in non-OID form: $oid");
                }
                # check LDAP first..
                if ($e) {
                    if (my $k = $an_2_ldap->{$oid}) {
                        if (my $v = $e->get_value($k)) {
                            $assertion_attributes->{$oid} = $v;
                            warn "[debug] SAML2 - attribute search for $oid (@{[$an_2_ldap->{$oid}]}) satisfied by LDAP: '$v'\n" if $ENV{MERITCOMMONS_DEBUG};

                            # LDAP satisfied this attribute, no need to check MeritCommons
                            next;
                        }
                        
                        # try using the first value of cn for 'displayName' 
                        if ($oid eq "urn:oid:2.16.840.1.113730.3.1.241") {
                            if (my $v = $e->get_value('cn')) {
                                $assertion_attributes->{$oid} = $v;
                                warn "[debug] SAML2 - attribute search for $oid (@{[$an_2_ldap->{$oid}]}) satisfied by LDAP: '$v'\n" if $ENV{MERITCOMMONS_DEBUG};

                                # LDAP satisfied this attribute.
                                next;
                            }
                        }
                    }
                    warn "[debug] SAML2 - attribute search for $oid (@{[$an_2_ldap->{$oid}]}) not satisfied by LDAP.\n" if $ENV{MERITCOMMONS_DEBUG};
                }

                my $an2ak = $an_2_meritcommons->{$oid};
                if ($an2ak && (my $v = $user->$an2ak)) {
                    $assertion_attributes->{$oid} = $v;
                    warn "[debug] SAML2 - attribute search for $oid (@{[$an_2_meritcommons->{$oid}]}) satisfied by MeritCommons: '$v'\n" if $ENV{MERITCOMMONS_DEBUG};
                } elsif ($oid eq 'urn:oid:1.3.6.1.4.1.5923.1.1.1.6') {
                    $assertion_attributes->{$oid} = "@{[$user->userid]}\@$eppn_domain";
                    warn "[debug] SAML2 - attribute search for $oid (eduPersonPrincipalName) satisfied by MeritCommons: '$assertion_attributes->{$oid}'\n" if $ENV{MERITCOMMONS_DEBUG};
                } elsif ($oid eq 'urn:oid:1.3.6.1.4.1.5923.1.1.1.9') {
                    $assertion_attributes->{$oid} = \@scoped_affiliations;
                    warn "[debug] SAML2 - attribute search for $oid (eduPersonScopedAffiliation) satisfied by MeritCommons: '@{[join(', ', @scoped_affiliations)]}'\n" if $ENV{MERITCOMMONS_DEBUG};
                } elsif ($oid eq 'urn:oid:1.3.6.1.4.1.5923.1.1.1.1') {
                    $assertion_attributes->{$oid} = \@affiliations;
                    warn "[debug] SAML2 - attribute search for $oid (eduPersonAffiliation) satisfied by MeritCommons: '@{[join(', ', @affiliations)]}'\n" if $ENV{MERITCOMMONS_DEBUG};
                } elsif ($oid eq 'urn:oid:1.3.6.1.4.1.5923.1.1.1.10') {
                    my $targeted_id = "@{[$self->saml2->entity_id]}!$entity_id!@{[$user->unique_id]}";
                    $assertion_attributes->{$oid} = $targeted_id;
                    warn "[debug] SAML2 - attribute search for $oid (eduPersonTargetedId) satisfied by MeritCommons: '$targeted_id'\n" if $ENV{MERITCOMMONS_DEBUG};
                } elsif ($oid eq 'urn:oid:1.3.6.1.4.1.25178.1.2.9') {
                    my $schac_domain = $self->saml2->eppn_domain;
                    $assertion_attributes->{$oid} = $schac_domain;
                    warn "[debug] SAML2 - attribute search for $oid (schacHomeOrganization) satisfied by MeritCommons: '$schac_domain'\n" if $ENV{MERITCOMMONS_DEBUG};
                } else {
                    $self->app->emit('saml2_unknown_attribute_requested', $self, $oid, $e);
                    if (my $hr = $self->stash("saml2.$oid")) {
                        $assertion_attributes->{$oid} = $hr->{attribute_value};
                        $an_2_ldap->{$oid} = $hr->{friendly_name} if $hr->{friendly_name};
                        $self->app->log->info("SAML2 - request for $hr->{friendly_name} ($oid) satisfied by unknown attribute event handler in $hr->{provider}");
                    } else {
                        warn "[debug] SAML2 - attribute search for $oid FAILED, omitting attribute\n" if $ENV{MERITCOMMONS_DEBUG};
                        $self->app->log->warn("SAML2 - Do not have the data to satisfy request for attribute $oid for $federation->{entity_id}");
                    }
                }
            }
        }

        # determine name_id, special cases first
        my $name_id_value;
        if ($name_id_attribute eq "eppn" || $name_id_attribute eq "eduPersonPrincipalName" || 
          $name_id_attribute eq "urn:oid:1.3.6.1.4.1.5923.1.1.1.6") {
            $name_id_value = "@{[$user->userid]}\@$eppn_domain";
        } elsif (lc($name_id_attribute) eq "edupersontargetedid" || $name_id_attribute eq "urn:oid:1.3.6.1.4.1.5923.1.1.1.10") {
            if (exists ($assertion_attributes->{'urn:oid:1.3.6.1.4.1.5923.1.1.1.10'}) && 
              $assertion_attributes->{'urn:oid:1.3.6.1.4.1.5923.1.1.1.10'}) {
                $name_id_value = $assertion_attributes->{'urn:oid:1.3.6.1.4.1.5923.1.1.1.10'};
            } else {
                $name_id_value = "@{[$self->saml2->entity_id]}!$entity_id!@{[$user->unique_id]}";
            }
        } else {
            unless ($name_id_value = $e->get_value($name_id_attribute)) {
                $name_id_value = $user->$name_id_attribute;
            }
        }

        # required to render the authn snippet!
        $self->stash(
            assertion_id => "_@{[$self->new_uuid]}",
            response_id => "_@{[$self->new_uuid]}",
            name_id => $name_id_attribute eq "eppn" ? "@{[$user->userid]}\@$eppn_domain" : 
                       $name_id_attribute eq "urn:oid:1.3.6.1.4.1.5923.1.1.1.10" ? $assertion_attributes->{$name_id_attribute} : 
                       $user->$name_id_attribute,
            name_id_format => $federation->{name_id_format} // 
                              $self->saml2->config->{name_id_format} // 
                              'urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified',
            attributes => $assertion_attributes,
            a2f => $an_2_ldap,
            sp_name_qualifier => $federation->{entity_id},
            idp_name_qualifier => "@{[$self->global_config->{front_door_url}]}/saml2/trust",
            restrictions => $federation->{audiences},
            # timestamps have to be fixed as we re-render for signatures...
            not_before => $self->saml2->timestamp(time - ($self->saml2->config->{not_before_skew} // 5)), # default to 5 seconds ago
            issue_instant => $self->saml2->timestamp, # also now
            not_after => $self->saml2->timestamp(
                Time::HiRes::time + ($self->saml2->config->{assertion_validity_time} || 3600)
            ), # default to 4 hours from now
        );

        # give our plugins a chance to override what's in the stash before generating the response!
        $self->app->emit('saml2_pre_authn_response', $self, $federation);

        $saml_response = $self->render_to_string(template => 'saml2_authn_response', format => 'xml');
        $self->stash(saml_response => b64_encode($saml_response, ''));
    } else {
        $self->app->log->error("SAML2 error: not enough arguments to generate_saml_response_for");
    }

    return $saml_response;
}

sub _artifact_response_to {
    my ($self, $entity_id) = @_;

    if (my $user = $self->active_user) {
        my $federation = $self->saml2->federation($entity_id);
        my $assertion_consumer_url =    $self->stash('assertion_consumer_url') //
                                        $federation->{assertion_consumer_url}->[0];

        if ($federation && $assertion_consumer_url) {
            if (my $saml_response = $self->saml2->generate_saml_response_for($entity_id, $user, $federation, $assertion_consumer_url)) {
                my ($artifact, $mh) = $self->generate_artifact();
                $self->cache->set(
                    $mh, $saml_response
                );

                my $acurl = Mojo::URL->new($assertion_consumer_url);
                $acurl->query([SAMLArt => $artifact]);
                $self->redirect_to($acurl);
            }
        } else {
            $self->app->log->error("@{[$user->userid]}'s SAML2 federation error: '$entity_id' not found, or cannot find assertion_consumer_url in federation agreement!");
            $self->reply->not_found;       
        }
    } else {
        $self->app->log->error("saml2.artifact_response_to called without active session!");
        $self->reply->not_found;        
    }
}

sub _post_response_to {
    my ($self, $entity_id) = @_;

    if (my $user = $self->active_user) {
        my $federation = $self->saml2->federation($entity_id);
        my $assertion_consumer_url =    $self->stash('assertion_consumer_url') //
                                        $federation->{assertion_consumer_url}->[0];

        if ($federation && $assertion_consumer_url) {

            # instantiate the assertion consumer URL object, and pull the attribute to use
            # for NameID out of the federation agreement
            my $acurl = Mojo::URL->new($assertion_consumer_url);

            $self->stash(
                destination_url => $acurl->to_string,
                relay_state =>  $self->stash('relay_state') // 
                                $self->param('RelayState') // 
                                $self->param('relay_state'),
            );

            if ($self->saml2->generate_saml_response_for($entity_id, $user, $federation, $assertion_consumer_url)) {
                $self->render(template => 'saml2_http_post_response');
            }
        } else {
            $self->app->log->error("@{[$user->userid]}'s SAML2 federation error: '$entity_id' not found, or cannot find assertion_consumer_url in federation agreement!");
            $self->reply->not_found;       
        }
    } else {
        $self->app->log->error("saml2.post_response_to called without active session!");
        $self->reply->not_found;        
    }
}

sub _inflate {
    my ($c, $buf) = @_;

    my ($i, $status) = Compress::Raw::Zlib::Inflate->new(
        AppendOutput => 1,
        Bufsize => 131072,
        WindowBits => -15,
    );

    my $inflated;
    do {
        $status = $i->inflate($buf, $inflated);
    } while ($status == Z_OK);

    unless ($status == Z_STREAM_END) {
        $c->app->log->error("saml2 - inflate error @{[$i->msg]}");
    }

    return $inflated;
}

sub _deflate {
    my ($c, $buf) = @_;

    my ($d, $status) = Compress::Raw::Zlib::Deflate->new(
        AppendOutput => 1,
        MemLevel => 8,
        WindowBits => -15
    );

    $status = $d->deflate($buf, my $out) if $status == Z_OK;
    $out .= $d->flush($out, Z_FINISH);
    
    unless ($status == Z_OK) {
        $c->app->log->error("saml2 - deflate error @{[$d->msg]}");
    }

    return $out;
}

sub _render_metadata {
    my ($c) = @_;
    my $md_file = "@{[$c->saml2->plugin->plugin_data_dir]}/metadata.xml";

    # generate the metadata file!
    $c->stash({ metadata_id => "_@{[$c->new_uuid]}", a2f => $an_2_ldap });
    my $md = $c->render_to_string(template => 'saml2_metadata', format => 'xml');
    Mojo::File->new($md_file)->spurt($md);
}

sub _authn_statement {
    my ($c) = @_;
    return trim($c->render_to_string(template => 'saml2_authn_statement', format => 'xml'));
}

sub _conditions_statement {
    my ($c, $restrictions) = @_;
    $c->stash(restrictions => $restrictions) if $restrictions; # use whats in the stash otherwise
    return trim($c->render_to_string(template => 'saml2_conditions', format => 'xml'));
}

sub _attribute_statement {
    my ($c, $attributes) = @_;
    $c->stash(attributes => $attributes) if $attributes; # use whats in the stash otherwise
    if (scalar(keys %{$c->stash->{attributes}})) {
        return trim($c->render_to_string(template => 'saml2_attribute_statement', format => 'xml'));
    } else {
        return '';
    }
}

sub _c14nize {
    my ($c, $string, $method) = @_;
    
    # autoflush all buffers...
    local $| = 1;
    if ($method) {
        if (my $subref = $c14n->{$method}) {
            # specified
            return $subref->($string);
        }
    }
    return $c14n->{$c->saml2->config->{c14n_method}}->($string);
}

sub _xml_sign {
    my ($c, $sk, $to_sign, $method) = @_;
    if ($method) {
        if (my $subref = $crypto->{$method}->{create}) {
            return $subref->($sk, $to_sign);
        }
    }

    # default
    return $crypto->{$c->saml2->config->{signature_method}}->{create}->($sk, $to_sign);
}

sub _xml_verify {
    my ($c, $pk, $to_verify, $sig, $method) = @_;
    if ($method) {
        if (my $subref = $crypto->{$method}->{verify}) {
            return $subref->($pk, $to_verify, $sig);
        }
    }

    # default
    return $crypto->{$c->saml2->config->{signature_method}}->{verify}->($pk, $to_verify, $sig);
}

sub _b64_digest {
    my ($c, $clear, $method) = @_;
    if ($method) {
        if (my $subref = $crypto->{$method}) {
            return $subref->($clear);
        }
    }

    # default
    return $crypto->{$c->saml2->config->{digest_method}}->($clear);
}

sub _signature_for {
    my ($self, $template, $id) = @_;

    # return an empty string if we're called in this context...
    if ($self->stash('signing_xml')) {
        return '';
    } else {
        # render the template we want to sign..., setting signing_xml to true so the embedded call to ourselves
        # returns ''.
        $self->stash(signing_xml => 1);
        my $doc = Mojo::DOM->new->xml(1)->parse($self->render_to_string(template => $template, format => 'xml'));
        $self->stash(signing_xml => 0);

        # get the xml to get a digest of...
        my $to_digest = $doc->find("[ID=\"$id\"]")->first;
        if ($to_digest) {
            my $to_digest_canon = $self->saml2->c14nize($to_digest->to_string);
            
            # generate the digest...
            $self->stash(
                digest_id => $id,
                digest_value => $self->saml2->b64_digest($to_digest_canon),
            );

            $self->stash(signed_info => 
                b($self->saml2->c14nize($self->render_to_string(template => 'xml_signed_info', format => 'xml')))
            );

            # sign the digest XML...
            $self->stash(signature_value => $self->saml2->xml_sign($self->saml2->rsa_sk, $self->stash('signed_info')));

            # render the final signature XML and return it to be included in the outer call
            return b(trim($self->render_to_string(template => 'xml_signature', format => 'xml')));
        } else {
            warn "[error]: SAML2 can't sign XML for $template/$id, not found.\n";
            return '';
        }
    }
}

sub _saml_timestamp {
    my ($self, $time) = @_;
    my $float = ".000Z";

    unless ($time) {
        $time = Time::HiRes::time;
    }

    if ($time =~ /\./) {
        ($float) = sprintf("%.03fZ", $time - int $time) =~ /^\d+(\.\d+Z)$/;
    }

    my $t = gmtime(int($time));
    my $timestamp = $t->datetime;
    $timestamp .= $float;
}

# returns the entity_id of the known entity that signed this document or undef if it was signed by someone we don't know...
# Note: if you pass in a Mojo::DOM object as the first argument it will be stripped of its signature block after calling this.
#       pass in an xml string if you wish to avoid this.
sub _verify_signed_xml {
    my ($self, $doc, $validate_signature_only, $allow_unsigned) = @_;

    # allow named attributes
    if (ref($doc) eq "HASH") {
        if ($doc->{validate_signature_and_issuer}) {
            $validate_signature_only = 0;
        } else {
            $validate_signature_only = $doc->{validate_signature_only};
        }
        $allow_unsigned = $doc->{allow_unsigned};
        $doc = $doc->{xml_document}
    }

    # if xml document was passed as a string, let's parse it now.
    unless (ref $doc eq "Mojo::DOM") {
        $doc = Mojo::DOM->new->xml(1)->parse($doc);
    }

    # If we have an Issuer specified, we'll use that for the entity id
    my $issuer = $doc->find('Issuer')->first;

    print "[saml2] verify_signed_xml - found @{[$issuer->text]}\n" if $issuer && $ENV{MERITCOMMONS_DEBUG};

    my $signatures = $doc->find('Signature');
    my $entity_id;

    print "[saml2] verify_signed_xml - found @{[$signatures->size]} signatures\n" if $ENV{MERITCOMMONS_DEBUG};

    if ($signatures->size == 1) {
        $signatures->each(sub {
            my ($sig) = @_;

            # first extract the id...
            my $id = $sig->find('Reference')->first->attr('URI');
            
            # get rid of the leading #
            $id =~ s/^\#//g;

            my $signed = $doc->find("[ID=\"$id\"]")->first;

            print "[saml2] verify_signed_xml - found signed document id $id\n" if $ENV{MERITCOMMONS_DEBUG};

            # strip out the signature...
            $signed->at('Signature')->remove;

            print "[saml2] verify_signed_xml - removed signature from XML\n" if $ENV{MERITCOMMONS_DEBUG};

            # strip out the whitespace left behind, we deal in strings from here on out...
            my $signed_xml = $signed->to_string;

            print "[saml2] verify_signed_xml - converted signed XML back into a string " . length($signed_xml) . " bytes in length\n" if $ENV{MERITCOMMONS_DEBUG};

            # canonicalize
            my $canonicalized = $self->saml2->c14nize($signed_xml, __get_reference_c14n_method_from_sig($sig));

            print "[saml2] verify_signed_xml - canonicalized signed XML string to new string " . length($canonicalized) . " bytes in length\n" if $ENV{MERITCOMMONS_DEBUG};

            # get the digest routine for this DigestMethod
            my $digest_method;
            my $dm_dom = $sig->find('DigestMethod')->first;
            if ($dm_dom) {
                $digest_method = $dm_dom->attr('Algorithm');
            }

            print "[saml2] verify_signed_xml - XML signed with digest method $digest_method\n" if $ENV{MERITCOMMONS_DEBUG};

            my $b64_digest = $self->saml2->b64_digest($canonicalized, $digest_method);

            if ($b64_digest eq $sig->find('DigestValue')->first->text) {
                # digests match.. verify signature..
                my $sig_cert = $sig->find('X509Certificate')->first;
                $sig_cert = $sig_cert->text if $sig_cert;

                my $e_id = $issuer->text if $issuer;

                # otherwise search all our federation agreements trying to figure out who signed this
                unless ($e_id) {
                    $e_id = $self->saml2->cert_to_entity_id($sig_cert);
                    if ($ENV{MERITCOMMONS_DEBUG} && $e_id) {
                        print "[saml2] verify_signed_xml - XML signed by known entity: $e_id\n";
                    }
                }

                my $pk = __get_pubkey_from_sig($sig);
                if ($pk) {
                    my $signed_info_dom = $sig->find('SignedInfo')->first;

                    # copy namespace from Signature if required
                    foreach my $key (keys %$sig) {
                        if ($key =~ /^xmlns/ && !$signed_info_dom->attr($key)) {
                            # we didn't define the namespace yet
                            $signed_info_dom->attr($key => $sig->{$key});
                        }
                    }

                    # canonicalized signature
                    my $canonicalized_signed_info_xml = $self->saml2->c14nize($signed_info_dom->to_string, __get_sig_c14n_method_from_sig($sig));

                    # extract the signature and signing method
                    my $signature_value_dom = $sig->find('SignatureValue')->first;
                    my $signature_method_dom = $sig->find('SignatureMethod')->first;

                    # get the signature method string out of the Algorithm attribute of SignatureMethod
                    my $signature_method;
                    if ($signature_method_dom) {
                        $signature_method = $signature_method_dom->attr('Algorithm');
                    }

                    if ($signature_value_dom) {
                        # actual verification..
                        if ($self->saml2->xml_verify( $pk, $canonicalized_signed_info_xml, $signature_value_dom->text, $signature_method )) {
                            if ($e_id) {
                                $entity_id = $e_id;
                            } else {
                                if ($validate_signature_only) {
                                    $entity_id = "UNKNOWN ENTITY; Signature-Valid";
                                } else {
                                    $self->app->log->error("XML signature was valid, but not signed by anyone we know...");
                                }
                            }
                        } else {
                            $self->app->log->error("problem validating XML signature, bad signature...");
                        }
                    }
                }
            } else {
                $self->app->log->error("problem validating XML signature, bad digest... $b64_digest vs. @{[$sig->find('DigestValue')->first->text]}");
            }
        });
    } else {
        if ($signatures->size == 0) {
            if ($allow_unsigned) {
                $self->app->log->warn("XML document is not signed, allow_unsigned is true, returning valid");
                if ($issuer) {
                    $entity_id = "@{[$issuer->text]}; Signature-Absent";
                } else {
                    $entity_id = "UNKNOWN ENTITY; Signature-Absent";
                }
            } else {
                $self->app->log->error("XML document is not signed, allow_unsigned is false, returning invalid");
                warn "[error] XML document is not signed, allow_unsigned is false, returning invalid\n";
            }
        } else {
            warn "[error] # of signatures found (@{[$signatures->size]}) > 1\n";
        }
    }

    return $entity_id;
}

sub __get_sig_c14n_method_from_sig {
    my ($sig) = @_;
    my $cm = $sig->at('SignedInfo > CanonicalizationMethod');

    if ($cm) {
        return $cm->attr('Algorithm');
    }

    return undef;    
}

sub __get_reference_c14n_method_from_sig {
    my ($sig) = @_;
    my $xfms = $sig->at('Reference > Transforms');
    if ($xfms) {
        foreach my $xfm (@{$xfms->children}) {
            if (exists $c14n->{$xfm->attr('Algorithm')} && defined $c14n->{$xfm->attr('Algorithm')}) {
                # the first c14n algorithm definition we know hot to handle!
                return $xfm->attr('Algorithm');
            }
        }
    }

    return undef;
}

sub __get_pubkey_from_sig {
    my ($sig) = @_;

    my $pubkey;
    my $x509_dom = $sig->find('X509Certificate')->first;
    if ($x509_dom) {
        my $x509 = Crypt::X509->new( cert => b64_decode($x509_dom->text) );
        $pubkey = Crypt::PK::RSA->new(\$x509->pubkey);
    }

    return $pubkey;
}

sub __clean_x509 {
    my ($cert) = @_;

    # rewrap the base64 data from the certificate; it may not be
    # wrapped at 64 characters as PEM requires
    $cert =~ s/(?:\s|\n)//g;
    
    my @lines;
    while (length $cert > 64) {
            push @lines, substr $cert, 0, 64, '';
        }
    push @lines, $cert;
    
    $cert = join "\n", @lines;

    $cert = "-----BEGIN CERTIFICATE-----\n" . $cert . "\n-----END CERTIFICATE-----\n";
    return $cert;
}

sub _verify_artifact {
    my ($self, $artifact) = @_;

    my ($tc, $ep_idx, $src_id, $mh) = unpack('ssa20a20', b64_decode($artifact));

    if ($tc == 4) {
        if ($src_id eq digest_data('SHA1', "@{[$self->global_config->{front_door_url}]}/saml2/trust")) {
            return b64_encode($mh, '');
        }
    }

    return undef;
}

# returns an artifact and a base64 encoded unique ID
# per SAML2 docs format: b64(TypeCode[2 bytes] . EndpointIndex[2 bytes] . IssuerSHA1 . randombytes_buf(20))
sub _generate_artifact {
    my ($self) = @_;

    my $mh = $self->random_string(20);
    my $src_id = digest_data('SHA1', "@{[$self->global_config->{front_door_url}]}/saml2/trust");

    return (b64_encode(
        pack('ssa20a20', 
            0x0004, 0x0000, # SAML V2.0 Artifact TypeCode and EndpointIndex
            $src_id,        # SAML V2.0 SourceID
            $mh             # SAML V2.0 MessageHandle
        ),
    ''), b64_encode($mh, ''));
}

1;
    
__DATA__

@@ saml2_artifact_response.xml.ep
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <samlp:ArtifactResponse xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" ID="<%= $response_id %>" Version="2.0" IssueInstant="<%= $issue_instant %>" <% if ($in_response_to) { %>InResponseTo="<%= $in_response_to %>" <% } %>>
<%== $c->saml2->signature_for('saml2_artifact_response', $response_id) %>
      <samlp:Status>
        <samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/>
      </samlp:Status>
<%== $saml_response %>
    </samlp:ArtifactResponse>
  </soap:Body>
</soap:Envelope> 

@@ saml2_artifact_resolve.xml.ep
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <samlp:ArtifactResolve xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" ID="<%= $response_id %>" Version="2.0" IssueInstant="<%= $issue_instant %>" Destination="<%= $c->global_config->{front_door_url} %>/saml2/ar">
      <Issuer xmlns="urn:oasis:names:tc:SAML:2.0:assertion"><%= $c->global_config->{front_door_url} %>/saml2/trust</Issuer>
<%== $c->saml2->signature_for('saml2_artifact_resolve', $response_id) %>
      <samlp:Artifact><%= $artifact %></samlp:Artifact>
    </samlp:ArtifactResolve>
  </soap:Body>
</soap:Envelope>

@@ saml2_authn_response.xml.ep
<samlp:Response ID="<%= $response_id %>" Version="2.0" IssueInstant="<%= $issue_instant %>" Destination="<%= $destination_url %>" Consent="urn:oasis:names:tc:SAML:2.0:consent:unspecified" <% if ($in_response_to) { %>InResponseTo="<%= $in_response_to %>" <% } %>xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol">
  <Issuer xmlns="urn:oasis:names:tc:SAML:2.0:assertion"><%= $c->global_config->{front_door_url} %>/saml2/trust</Issuer>
  <samlp:Status>
    <samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success" />
  </samlp:Status>
  <Assertion ID="<%= $assertion_id %>" IssueInstant="<%= $issue_instant %>" Version="2.0" xmlns="urn:oasis:names:tc:SAML:2.0:assertion">
    <Issuer><%= $c->global_config->{front_door_url} %>/saml2/trust</Issuer>
<%== $c->saml2->signature_for('saml2_authn_response', $assertion_id) %>
    <Subject>
      <NameID <% if ($idp_name_qualifier) { %>NameQualifier="<%= $idp_name_qualifier %>" <% } %><% if ($sp_name_qualifier) { %>SPNameQualifier="<%== $sp_name_qualifier %>" <% } %>Format="<%= $name_id_format %>"><%= $name_id %></NameID>
      <SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer">
        <SubjectConfirmationData <% if ($in_response_to) { %>InResponseTo="<%= $in_response_to %>" <% } %>NotOnOrAfter="<%= $not_after %>" Recipient="<%= $destination_url %>" />
      </SubjectConfirmation>
    </Subject>
    <%== $c->saml2->conditions_statement %>
    <%== $c->saml2->attribute_statement %>
    <%== $c->saml2->authn_statement %>
  </Assertion>
</samlp:Response>

@@ saml2_signed_authn_request.xml.ep
<samlp:AuthnRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" ID="<%= $request_id %>" Version="2.0" IssueInstant="<%= $issue_instant %>" ForceAuthn="<%= $force_authn // 'false' %>" ProtocolBinding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST">
    <Issuer xmlns="urn:oasis:names:tc:SAML:2.0:assertion"><%= $c->global_config->{front_door_url} %>/saml2/trust</Issuer>
<%== $c->saml2->signature_for('saml2_authn_request', $request_id) %>
    <samlp:NameIDPolicy Format="urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress" />
    <samlp:RequestedAuthnContext Comparison="exact">
        <AuthnContextClassRef>
            urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport
        </AuthnContextClassRef>
    </samlp:RequestedAuthnContext>
</samlp:AuthnRequest>

@@ saml2_authn_request.xml.ep
<samlp:AuthnRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" ID="<%= $request_id %>" Version="2.0" IssueInstant="<%= $issue_instant %>" ForceAuthn="<%= $force_authn // 'false' %>" ProtocolBinding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" AssertionConsumerServiceURL="<%= $c->global_config->{front_door_url} %>/saml2/ac">
    <Issuer xmlns="urn:oasis:names:tc:SAML:2.0:assertion"><%= $c->global_config->{front_door_url} %>/saml2/trust</Issuer>
    <samlp:NameIDPolicy Format="urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress" />
    <samlp:RequestedAuthnContext Comparison="exact">
        <AuthnContextClassRef>
            urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport
        </AuthnContextClassRef>
    </samlp:RequestedAuthnContext>
</samlp:AuthnRequest>

@@ saml2_conditions.xml.ep
<Conditions NotBefore="<%= $not_before %>" NotOnOrAfter="<%= $not_after %>">
      <% if (defined $restrictions && ref($restrictions) eq "ARRAY") { =%>
      <% foreach my $restriction (@$restrictions) { =%>
      <AudienceRestriction>
        <Audience><%= $restriction %></Audience>
      </AudienceRestriction>
      <% } =%>
      <% } =%>
    </Conditions>

@@ saml2_attribute_statement.xml.ep
<AttributeStatement>
      <% foreach my $attr (keys %$attributes) { =%>
      <Attribute <% if (my $fn = $a2f->{$attr}) { %>FriendlyName="<%= $fn %>" <% } %><% if ($attr =~ /^urn\:/) { %>NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri" <% } %>Name="<%= $attr %>">
      <% if (ref $attributes->{$attr} eq "ARRAY") { =%>
        <% foreach my $value (@{$attributes->{$attr}}) { =%>
        <AttributeValue><%= $value %></AttributeValue>
        <% } =%>
      <% } else { =%>
        <AttributeValue><%= $attributes->{$attr} %></AttributeValue>
      <% } =%>
      </Attribute>
      <% } =%>
    </AttributeStatement>

@@ saml2_authn_statement.xml.ep
<AuthnStatement AuthnInstant="<%= $c->saml2->timestamp($c->meritcommons_session->create_time) %>" SessionIndex="<%= $c->meritcommons_session->session_id %>">
      <AuthnContext>
        <AuthnContextClassRef>urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport</AuthnContextClassRef>
      </AuthnContext>
    </AuthnStatement>

@@ xml_signature.xml.ep
<ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
<%= $signed_info %>
  <ds:SignatureValue><%= $signature_value %></ds:SignatureValue>
  <ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
    <ds:X509Data>
      <ds:X509Certificate><%= $c->saml2->x509_string %></ds:X509Certificate>
    </ds:X509Data>
  </ds:KeyInfo>
</ds:Signature>

@@ xml_signed_info.xml.ep
<ds:SignedInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
  <ds:CanonicalizationMethod Algorithm="<%= $c->saml2->config->{c14n_method} %>" />
  <ds:SignatureMethod Algorithm="<%= $c->saml2->config->{signature_method} %>" />
  <ds:Reference URI="#<%= $digest_id %>">
    <ds:Transforms>
      <ds:Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature" />
      <ds:Transform Algorithm="<%= $c->saml2->config->{c14n_method} %>" />
    </ds:Transforms>
    <ds:DigestMethod Algorithm="<%= $c->saml2->config->{digest_method} %>" />
    <ds:DigestValue><%= $digest_value %></ds:DigestValue>
  </ds:Reference>
</ds:SignedInfo>

@@ saml2_logout_response.xml.ep
<?xml version="1.0" encoding="utf-8"?>
<samlp:LogoutResponse xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="<%= $response_id %>" Version="2.0" IssueInstant="<%= $issue_instant %>" Destination="<%= $assertion_consumer_url %>" InResponseTo="<%= $in_response_to %>">
    <saml:Issuer><%= $c->global_config->{front_door_url} %>/saml2/trust</saml:Issuer>
<%== $c->saml2->signature_for('saml2_logout_response', $response_id) %>
    <samlp:Status xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol">
        <samlp:StatusCode Value="<%= $status_code %>" />
        <samlp:StatusMessage><%= $status_message %></samlp:StatusMessage>
    </samlp:Status>
</samlp:LogoutResponse>

@@ saml2_metadata.xml.ep
<?xml version="1.0" encoding="utf-8"?>
<EntityDescriptor ID="<%= $metadata_id %>" entityID="<%= $c->global_config->{front_door_url} %>/saml2/trust" xmlns="urn:oasis:names:tc:SAML:2.0:metadata">
<%== $c->saml2->signature_for('saml2_metadata', $metadata_id) =%>
  <Extensions xmlns:mdrpi="urn:oasis:names:tc:SAML:metadata:rpi" xmlns:alg="urn:oasis:names:tc:SAML:metadata:algsupport">
    <alg:DigestMethod Algorithm="<%= $c->saml2->config->{digest_method} %>"/>
    <alg:SigningMethod Algorithm="<%= $c->saml2->config->{signature_method} %>"/>
    <mdrpi:RegistrationInfo registrationAuthority="<%= $c->saml2->config->{federation_registration_authority} // 'https://incommon.org/' %>"/>
    <mdrpi:PublicationInfo publisher="<%= $c->saml2->config->{federation_registration_publisher} // 'http://md.incommon.org/InCommon/InCommon-metadata-preview.xml'%>" creationInstant="<%= $c->saml2->config->{federation_registration_creation_instant} // '2015-02-04T10:00:00Z'%>"/>
  </Extensions>

  <Organization>
    <OrganizationName xml:lang="en"><%= $self->config->{service_organization} %></OrganizationName>
    <OrganizationDisplayName xml:lang="en"><%= $self->config->{service_organization} %></OrganizationDisplayName>
    <OrganizationURL xml:lang="en"><%= $self->config->{service_home_url} %></OrganizationURL>
  </Organization>

% if (exists $self->saml2->config->{contact_persons} && ref $self->saml2->config->{contact_persons} eq "ARRAY") {
%   foreach my $person (@{$self->saml2->config->{contact_persons}}) {  
    <ContactPerson ContactType="<%= $person->{type} %>" <%== exists $person->{additional_ct_attributes} ? " " . $person->{additional_ct_attributes} : '' =%>>
% if ($person->{given_name}) {      
      <GivenName><%= $person->{given_name} %></GivenName>
% }
% if ($person->{surname}) {
      <SurName><%= $person->{surname} %></SurName>
% }
% if ($person->{email_address}) {
      <EmailAddress><%= $person->{email_address} %></EmailAddress>
% }
    </ContactPerson>
%   }
% } else {
  <ContactPerson contactType="administrative">
    <GivenName><%= $self->config->{administrator_common_name} %></GivenName>
    <EmailAddress><%= $self->config->{administrator_email} %></EmailAddress>
  </ContactPerson>
% }
  
  <SPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol" WantAssertionsSigned="true">
    <KeyDescriptor use="signing">
      <ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
        <ds:X509Data>
          <ds:X509Certificate><%= $c->saml2->x509_string %></ds:X509Certificate>
        </ds:X509Data>
      </ds:KeyInfo>
    </KeyDescriptor>

    <Extensions>
      <mdui:UIInfo xmlns:mdui="urn:oasis:names:tc:SAML:metadata:ui">
        <mdui:DisplayName xml:lang="en"><%= $self->config->{service_organization} %> MeritCommons</mdui:DisplayName>
        <mdui:Description xml:lang="en"><%= $self->version_banner %></mdui:Description>
        <mdui:InformationURL xml:lang="en"><%= $self->config->{help_url} %></mdui:InformationURL>
        <mdui:PrivacyStatementURL xml:lang="en"><%= $self->config->{service_privacy_url} %></mdui:PrivacyStatementURL>
        <mdui:Logo height="48" width="48" xml:lang="en"><%= $self->config->{service_logo_url} || $c->asset_url('img/meritcommons_logo_48x48.png') %></mdui:Logo>
      </mdui:UIInfo>
% if ($self->saml2->config->{assert_sirtfi_compliance}) {     
      <mdattr:EntityAttributes xmlns:mdattr="urn:oasis:names:tc:SAML:metadata:attribute">
        <saml:Attribute xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri" Name="urn:oasis:names:tc:SAML:attribute:assurance-certification">
          <saml:AttributeValue>https://refeds.org/sirtfi</saml:AttributeValue>
        </saml:Attribute>
      </mdattr:EntityAttributes>
% }
    </Extensions>

    <SingleLogoutService isDefault="true" Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="<%= $self->global_config->{front_door_url} %>/saml2/logout"/>
    <NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress</NameIDFormat>
    <NameIDFormat>urn:mace:shibboleth:1.0:nameIdentifier</NameIDFormat>
    <NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified</NameIDFormat>
    <NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:transient</NameIDFormat>
    <NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:persistent</NameIDFormat>
    <AssertionConsumerService isDefault="true" index="1" Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="<%= $self->global_config->{front_door_url} %>/saml2/sp/http_post"/>
% if (exists $self->saml2->config->{requested_attributes} && ref $self->saml2->config->{requested_attributes} eq "ARRAY") {
    <AttributeConsumingService index="1">
%   foreach my $urn (@{$self->saml2->config->{requested_attributes}}) {
%     if (exists $a2f->{$urn} && $a2f->{$urn}) {
      <RequestedAttribute FriendlyName="<%= $a2f->{$urn} %>" Name="<%== $urn %>"/>
%     }
%   }
    </AttributeConsumingService>
% }
  </SPSSODescriptor>

  <IDPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
    <KeyDescriptor use="signing">
      <ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
        <ds:X509Data>
          <ds:X509Certificate><%= $c->saml2->x509_string %></ds:X509Certificate>
        </ds:X509Data>
      </ds:KeyInfo>
    </KeyDescriptor>
    <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="<%= $self->global_config->{front_door_url} %>/saml2/http_post" />
    <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="<%= $self->global_config->{front_door_url} %>/saml2/http_redirect" />
    <SingleLogoutService isDefault="true" Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="<%= $self->global_config->{front_door_url} %>/saml2/logout"/>
    <ArtifactResolutionService isDefault="true" index="0" Binding="urn:oasis:names:tc:SAML:2.0:bindings:SOAP" Location="<%= $self->global_config->{front_door_url} %>/saml2/ar" />
    <NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:persistent</NameIDFormat>
    <NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified</NameIDFormat>
    <NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:transient</NameIDFormat>
    <NameIDFormat>urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress</NameIDFormat>
    <Extensions>
      <mdui:UIInfo xmlns:mdui="urn:oasis:names:tc:SAML:metadata:ui">
        <mdui:DisplayName xml:lang="en"><%= $self->config->{service_organization} %> MeritCommons</mdui:DisplayName>
        <mdui:Description xml:lang="en"><%= $self->version_banner %></mdui:Description>
        <mdui:InformationURL xml:lang="en"><%= $self->config->{help_url} %></mdui:InformationURL>
        <mdui:PrivacyStatementURL xml:lang="en"><%= $self->config->{service_privacy_url} %></mdui:PrivacyStatementURL>
        <mdui:Logo height="48" width="48" xml:lang="en"><%= $self->config->{service_logo_url} || $c->asset_url('img/meritcommons_logo_48x48.png') %></mdui:Logo>
      </mdui:UIInfo>
% if ($self->saml2->config->{assert_sirtfi_compliance}) {     
      <mdattr:EntityAttributes xmlns:mdattr="urn:oasis:names:tc:SAML:metadata:attribute">
        <saml:Attribute xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri" Name="urn:oasis:names:tc:SAML:attribute:assurance-certification">
          <saml:AttributeValue>https://refeds.org/sirtfi</saml:AttributeValue>
        </saml:Attribute>
      </mdattr:EntityAttributes>
% }
      <Scope xmlns="urn:mace:shibboleth:metadata:1.0" regexp="false"><%= $self->saml2->eppn_domain %></Scope>
    </Extensions>
  </IDPSSODescriptor>
</EntityDescriptor>

@@ saml2_http_post_response.html.ep
<!doctype html>
<html>
  <body>
    <form id="saml-http-post" method="post" action="<%= $destination_url %>" />
        <input type="hidden" name="SAMLResponse" value="<%= $saml_response %>"/>
        <% if (my $relay_state = $c->stash('relay_state')) { %>
            <input type="hidden" name="RelayState" value="<%= $relay_state %>"/>
        <% } %>
        <% if (my $wreply = $c->stash('wreply')) { %>
            <input type="hidden" name="wreply" value="<%= $wreply %>"/>
        <% } %>
    </form>
    <script>document.forms[0].submit();</script>
  </body>
</html>
