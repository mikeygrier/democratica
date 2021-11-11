package Praux::Util::Zimbra::SOAP;

use SOAP::Lite;
# make some accessors..
use base qw/Praux Class::Accessor/;
__PACKAGE__->mk_accessors(qw/ auth soap mh /);

our $context;

sub new {
    my ($class, $mh) = @_;
    my ($soap) = SOAP::Lite->readable(1)->uri('urn:zimbraAdmin')->proxy("https://" . $mh . ":7071/service/admin/soap");

    my $praux = new Praux;

    # geto our datas pls.
    my $self = {
        soap        =>      $soap,
        auth        =>      $soap->AuthRequest(
            SOAP::Data->name(account        =>      $praux->c->ZIMBRA_ADMIN_LOGIN),
            SOAP::Data->name(password       =>      $praux->c->ZIMBRA_ADMIN_PASS),
        )->body->{AuthResponse},
        mh          =>      $mh,
    };

    return bless($self, $class);
}

sub AUTOLOAD {
    my ($self, $args, $subpath) = @_;

    # i can has ur methodz now? kthx.
    my ($method) = $AUTOLOAD =~ /^.+::([\w\_]+)$/;

    # i like you guys.  i do.
    my ($request, $response);

    # do a pretty transform here
    if ($method =~ /_/) {
        @components = split(/_/, $method);
        $request = join('', map { ucfirst($_) } @components, "request");
        $response = join('', map { ucfirst($_) } @components, "response");
    }

    die "[error] Zimbra soap service not listening on " . $self->{mh} . "\n" unless $self->auth && $self->soap;

    # make sure we have our context. lazily. it will persist in mod_perl NO LONGER :D.
    unless ($context) {
        $context = SOAP::Header->name(q/context/)->value(
            [
                map { SOAP::Header->name($_)->value($self->auth->{$_}) } qw/authToken sessionId/
            ],
        )->attr( { xmlns => 'urn:zimbra' });
    }

    # now we'll build the argument stack.
    my @arguments = ($context); # context is first.

    # pull our method attributes out.
    my $method_attributes = delete $args->{_method_attributes} || {};

    # named arguments
    foreach my $key (keys %$args) {
        push(@arguments, SOAP::Data->attr($method_attributes)->name( $key => $args->{$key} ));
    }

    # now our payload attributes
    my $attributes = delete $args->{_attributes} || {};

    # now iterate thru these attribs.
    if ($attributes && scalar(keys %$attributes) >= 1) {
        foreach my $attr (keys %$attributes) {
            if (ref($attributes->{$attr}) eq "ARRAY") {
                # MULTI VALUE
                foreach my $val (@{$attributes->{$attr}}) {
                    my $attr_obj = SOAP::Data->attr({ n => $attr })->name( a => $val );
                    if ($attributes->{$attr} =~ /^(true|false)$/i) {
                        $attr_obj->type('xsd:boolean');
                    }
                    push(@arguments, $attr_obj);
                }
            } else {
                # SINGLE VALUE
                my $attr_obj = SOAP::Data->attr({ n => $attr })->name( a => $attributes->{$attr} );
                if ($attributes->{$attr} =~ /^(true|false)$/i) {
                    $attr_obj->type('xsd:boolean');
                }
                push(@arguments, $attr_obj);
            }
        }
    }

    # ok, we should be uhm.. fairly "fresh" as it were.
    my $returned = $self->soap->$request(@arguments);

    if (my $error = $returned->dataof('Body/Fault')) {
        my $ed = $error->value;

        # throw this out, so we get a new one.
        undef($context);

        if ($ed->{faultstring}) {
            die "Fatal SOAP Error: " . $error->value->{faultstring} . "\n";
        } elsif (exists($ed->{Reason}->{Text})) {
            die "Fatal SOAP Error: " . $ed->{Reason}->{Text} . "\n";
        }
    }
    return ($subpath ? $returned->dataof("Body/$response/$subpath") : $returned->dataof("Body/$response/[1]"));
}

# goodbye, cruel world.
sub DESTROY {
    1;
}

1;