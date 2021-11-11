package MeritCommons::Plugin::CasServer::ServiceResponse;

use XML::Writer;
use POSIX qw(strftime);
use Time::HiRes qw(time gettimeofday);
use UUID::Tiny;

use constant PROXY_TYPE => 1;
use constant SERVICE_VALIDATE_TYPE => 2;
use constant PROXY_VALIDATE_TYPE => 3;
use constant SAML_VALIDATE_TYPE => 4;

require Exporter;
our @ISA; 
push(@ISA, 'Exporter');

our @EXPORT = qw(
    PROXY_TYPE
    SERVICE_VALIDATE_TYPE
    PROXY_VALIDATE_TYPE
    SAML_VALIDATE_TYPE
);

sub new {
    my ($class, $type) = @_;
    my $self = {};
    bless $self, $class;

    $self->{_type} = $type;

    return $self;
}

sub _generate_response {
    my ($self) = @_;

    my $xml = new XML::Writer(OUTPUT => 'self');
    $xml->startTag("cas:serviceResponse", "xmlns:cas" => "http://www.yale.edu/tp/cas");

    foreach my $proxy_success (@{ $self->{_proxy_successes} }) {
        $xml->startTag("cas:proxySuccess");
        $xml->startTag("cas:proxyTicket");
        $xml->characters($proxy_success->{proxy_ticket});
        $xml->endTag("cas:proxyTicket");
        $xml->endTag("cas:proxySuccess");
    }

    foreach my $proxy_failure (@{ $self->{_proxy_failures} }) {
        $xml->startTag("cas:proxyFailure", "code" => $proxy_failure->{code});
        $xml->characters($proxy_failure->{message});
        $xml->endTag("cas:proxyFailure");
    }

    foreach my $authentication_failure (@{ $self->{_authentication_failures} }) {
        $xml->startTag("cas:authenticationFailure", "code" => $authentication_failure->{code});
        $xml->characters($authentication_failure->{message});
        $xml->endTag("cas:authenticationFailure");
    }

    foreach my $authentication_success (@{ $self->{_authentication_successes} }) {
        $xml->startTag("cas:authenticationSuccess");
        $xml->startTag("cas:user");
        $xml->characters($authentication_success->{user});
        $xml->endTag("cas:user");

        # attributes should not be displayed for the proxyValidate method
        if ($self->{_type} == $self->SERVICE_VALIDATE_TYPE) {
            $xml->startTag('cas:attributes');
            foreach my $attribute (@{ $self->{_attributes} }) {
                $xml->startTag('cas:' . $attribute->{name});
                $xml->characters($attribute->{value});
                $xml->endTag('cas:' . $attribute->{name});
            }      
            $xml->endTag('cas:attributes');
        }

        foreach my $proxy_granting_ticket (@{ $self->{_proxy_granting_tickets} }) {
            $xml->startTag("cas:proxyGrantingTicket");
            $xml->characters($proxy_granting_ticket->{pgt_iou_id});
            $xml->endTag("cas:proxyGrantingTicket");
        }

        if ($self->{_proxies}) {
            $xml->startTag("cas:proxies");

            foreach my $proxy (@{ $self->{_proxies} }) {
                $xml->startTag("cas:proxy");
                $xml->characters($proxy);
                $xml->endTag("cas:proxy");
            }

            $xml->endTag("cas:proxies");
        }

        $xml->endTag("cas:authenticationSuccess");
    }

    $xml->endTag("cas:serviceResponse");
    $xml->end();
    return $xml->to_string();
}

sub _generate_validate_saml_response {
    my ($self) = @_;

    my $xml = new XML::Writer(OUTPUT => 'self');
    $xml->startTag("SOAP-ENV:Envelope", "xmlns:SOAP-ENV" => "http://schemas.xmlsoap.org/soap/envelope/");
    $xml->startTag("SOAP-ENV:Body");

    $has_errors = ((scalar @{$self->{_authentication_failures}}) > 0) || ((scalar @{$self->{_proxy_failures}}) > 0) ;

    if ($self->{_authenticated_user} && !$has_errors) {
        # allow not before skew to be configurable and default to no skew (0 seconds)
        $not_before_skew = $self->{_saml_not_before_skew} ? $self->{_saml_not_before_skew} : 0;

        # allow assertion expirations to be configurable and default to 30 seconds
        $assertion_expiration = $self->{_assertion_expiration} ? $self->{_assertion_expiration} : 30;

        my @issue_time = gmtime(time - $not_before_skew);
        my @not_after = gmtime(time + $assertion_expiration);

        $xml->startTag("saml1p:Response",
           "xmlns:saml1p" => "urn:oasis:names:tc:SAML:1.0:protocol",
           "IssueInstant" => $self->saml_timestamp(@issue_time),
           "MajorVersion" => "1",
           "MinorVersion" => "1",
           "Recipient" => $self->{_service},
           "ResponseID" => $self->saml_uuid(),
        );

        $xml->startTag("saml1p:Status");
        $xml->startTag("saml1p:StatusCode", "Value" => "saml1p:Success");
        $xml->endTag("saml1p:StatusCode");
        $xml->endTag("saml1p:Status");

        $xml->startTag("saml1:Assertion",
            "xmlns:saml1" => "urn:oasis:names:tc:SAML:1.0:assertion",
            "AssertionID" => $self->saml_uuid(),
            "IssueInstant" => $self->saml_timestamp(@issue_time),
            "Issuer" => "localhost",
            "MajorVersion" => "1",
            "MinorVersion" => "1"
        );

        $xml->startTag("saml1:Conditions",
            "NotBefore" => $self->saml_timestamp(@issue_time),
            "NotOnOrAfter" => $self->saml_timestamp(@not_after)
        );

        $xml->startTag("saml1:AudienceRestrictionCondition");
        $xml->startTag("saml1:Audience");
        $xml->characters($self->{_service});
        $xml->endTag("saml1:Audience");
        $xml->endTag("saml1:AudienceRestrictionCondition");
        $xml->endTag("saml1:Conditions");

        $xml->startTag("saml1:AuthenticationStatement",
            "AuthenticationInstant" => $self->saml_timestamp(@issue_time),
            "AuthenticationMethod" => "urn:oasis:names:tc:SAML:1.0:am:unspecified");
        $xml->startTag("saml1:Subject");
        $xml->startTag("saml1:NameIdentifier");
        $xml->characters($self->{_authenticated_user});
        $xml->endTag("saml1:NameIdentifier");
        $xml->startTag("saml1:SubjectConfirmation");
        $xml->startTag("saml1:ConfirmationMethod");
        $xml->characters("urn:oasis:names:tc:SAML:1.0:cm:artifact");
        $xml->endTag("saml1:ConfirmationMethod");
        $xml->endTag("saml1:SubjectConfirmation");
        $xml->endTag("saml1:Subject");
        $xml->endTag("saml1:AuthenticationStatement");

        $xml->startTag("saml1:AttributeStatement");
        $xml->startTag("saml1:Subject");
        $xml->startTag("saml1:NameIdentifier");
        $xml->characters($self->{_authenticated_user});
        $xml->endTag("saml1:NameIdentifier");
        $xml->startTag("saml1:SubjectConfirmation");
        $xml->startTag("saml1:ConfirmationMethod");
        $xml->characters("urn:oasis:names:tc:SAML:1.0:cm:artifact");
        $xml->endTag("saml1:ConfirmationMethod");
        $xml->endTag("saml1:SubjectConfirmation");
        $xml->endTag("saml1:Subject");

        foreach my $attribute (@{ $self->{_attributes} }) {
            $xml->startTag("saml1:Attribute", "AttributeName" => $attribute->{name}, "AttributeNamespace" => "http://www.ja-sig.org/products/cas/");
            $xml->startTag("saml1:AttributeValue", "xmlns:xs" => "http://www.w3.org/2001/XMLSchema", "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance", "xsi:type" => "xs:string");
            $xml->characters($attribute->{value});
            $xml->endTag("saml1:AttributeValue");
            $xml->endTag("saml1:Attribute");
        }

        $xml->endTag("saml1:AttributeStatement");
        $xml->endTag("saml1:Assertion");        
        $xml->endTag("saml1p:Response");
    } else {
        my @error_messages;

        foreach my $proxy_failure (@{ $self->{_proxy_failures} }) {
            push(@error_messages, $proxy_failure->{message});
        }

        foreach my $authentication_failure (@{ $self->{_authentication_failures} }) {
            push(@error_messages, $authentication_failure->{message});
        }

        my $error_message = join(", ", @error_messages);

        $xml->startTag("SOAP-ENV:Fault");
        $xml->startTag("faultcode");
        $xml->characters("env:Client");
        $xml->endTag("faultcode");
        $xml->startTag("faultstring");
        $xml->characters($error_message);
        $xml->endTag("faultstring");
        $xml->endTag("SOAP-ENV:Fault")
    }

    $xml->endTag("SOAP-ENV:Body");
    $xml->endTag("SOAP-ENV:Envelope");
    $xml->end();

    return $xml->to_string();
}

sub add_authentication_failure {
    my ($self, $code, $message) = @_;

    push(
        @{ $self->{_authentication_failures} },
        {
            code    => $code,
            message => $message
        }
    );
}

sub add_attribute {
    my ($self, $name, $value) = @_;

    push(
        @{ $self->{_attributes} },
        {
            name    => $name,
            value => $value
        }
    );
}

sub add_authentication_success {
    my ($self, $user) = @_;

    push(
        @{ $self->{_authentication_successes} },
        {
            user => $user
        }
    );
}

sub add_proxy_granting_ticket {
    my ($self, $pgt_iou_id) = @_;

    push(
        @{ $self->{_proxy_granting_tickets} },
        {
            pgt_iou_id => $pgt_iou_id
        }
    );
}

sub add_proxy_success {
    my ($self, $pt_id) = @_;

    push(
        @{ $self->{_proxy_successes} },
        {
            proxy_ticket => $pt_id
        }
    );
}

sub add_proxy_failure {
    my ($self, $code, $message) = @_;

    push(
        @{ $self->{_proxy_failures} },
        {
            code    => $code,
            message => $message
        }
    );
}

sub get_service {
    my ($self) = @_;    
    return $self->{_service};
}

# plain setter/getter
sub proxies {
    my ($self, $proxies) = @_;

    if ($proxies) {
        $self->{_proxies} = $proxies;
    }

    return $self->{_proxies};
}

sub saml_timestamp {
    my ($self, @gmtime) = @_;
    my ($seconds, $microseconds) = gettimeofday;
    $microseconds = substr($microseconds,0,2);
    return strftime("%Y-%m-%dT%H:%M:%S.", @gmtime) . $microseconds . "Z";
}

sub saml_uuid {
    my ($self) = @_;
    my $uuid = lc(create_UUID_as_string(UUID_V4));
    $uuid =~ s/(_|-)//g;
    $uuid = '_' . substr($uuid, 0, 32);
    return $uuid;
}

sub set_authenticated_user {
    my ($self, $authenticated_user) = @_;
    $self->{_authenticated_user} = $authenticated_user;
}

sub set_saml_assertion_expiration {
    my ($self, $saml_assertion_expiration) = @_;
    $self->{_saml_assertion_expiration} = $saml_assertion_expiration;
}

sub set_saml_not_before_skew {
    my ($self, $saml_not_before_skew) = @_;
    $self->{_saml_not_before_skew} = $saml_not_before_skew;
}

sub set_service {
    my ($self, $service) = @_;
    $self->{_service} = $service;
}

sub to_string {
    my ($self) = @_;
    if (($self->{_type} == $self->PROXY_TYPE) || ($self->{_type} == $self->SERVICE_VALIDATE_TYPE) || ($self->{_type} == $self->PROXY_VALIDATE_TYPE)) {
        return $self->_generate_response;
    } elsif ($self->{_type} == $self->SAML_VALIDATE_TYPE) {
        return $self->_generate_validate_saml_response;
    }
}

1;
