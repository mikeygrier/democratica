# this is used to provision zimbra DL's for use in forwarding email..
package Praux::Util::Zimbra;

use Net::LDAP;
use Praux::Util::Zimbra::SOAP;
use base qw/Praux Class::Accessor/;

__PACKAGE__->mk_accessors(qw/ resume /);

sub new {
    my ($class, %attrs) = @_;
    return bless (\%attrs, $class);
}

sub enable_mailmask {
    my ($self) = @_;
    if ($self->mailmask_enabled) {
        return 0;
    }
    
    my $id = $self->soap->create_distribution_list(
        {
            name => lc($self->resume->instance . '@' . "praux.com"),
            _attributes => {
                displayName     =>      $self->resume->name,
                zimbraHideInGAL =>      'TRUE',
            },
        }
    )->attr->{id};
    
    if ($id) {
        # add the forwarding address as the member!
        $self->soap->add_distribution_list_member(
            {
                id => $id,
                dlm => $self->resume->email,
            }
        );
    } else {
        die "Error creating Zimbra DUL!\n";
    }
    return 1;
}

sub disable_mailmask {
    my ($self) = @_;
    unless ($self->mailmask_enabled) {
        return 0;
    }
    
    if (my $id = $self->resolve_zimbra_uuid) {
        $self->soap->delete_distribution_list(
            {
                id => $id,
                _method_attributes => {
                    by => 'id',
                },
            },
        );
    }
}

sub toggle_mailmask {
    my ($self) = @_;
    if ($self->mailmask_enabled) {
        return $self->disable_mailmask;
    } else {
        return $self->enable_mailmask;
    }
}

sub mailmask_enabled {
    my ($self) = @_;
    foreach my $oc ($self->zimbra_ldap_attribute('objectClass')) {
        if ($oc eq "zimbraDistributionList") {
            return 1;
        }
    }
    return 0;
}

sub resolve_zimbra_uuid {
    my ($self) = @_;
    return $self->zimbra_ldap_attribute('zimbraId');
}

sub zimbra_ldap_attribute {
    my ($self, $attr) = @_;
    my $res = $self->zimbra_ldap->search(
        base    =>      'ou=people,dc=praux,dc=com',
        filter  =>      'zimbraMailAlias=' . $self->resume->instance . '@praux.com',
    );

    if ($res->code) {
        die "LDAP Error: " . $res->error . "\n";
    }

    if ($res->count == 1) {
        # we have one..
        return $res->entry(0)->get_value($attr);
    } elsif ($res->count == 0) {
        warn "LDAP Error: unable to find zimbra account\n";
    } else {
        warn "LDAP Error: non unique account\n";
    }

    return undef;
}

sub zimbra_ldap {
    my ($self) = @_;
    my $ldap = Net::LDAP->new($self->c->ZIMBRA_LDAP_SERVER);
    $ldap->bind($self->c->ZIMBRA_BIND_DN,
        password    =>      $self->c->ZIMBRA_ADMIN_PASS,
        version     =>      3,
    );
    return $ldap;
}

# we're not caching these!
sub soap {
    my ($self, $recache) = @_;
    return Praux::Util::Zimbra::SOAP->new($self->c->ZIMBRA_MAIL_HOST);
}

1;