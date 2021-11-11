package WWW::Romeo::Extension;

use WWW::Romeo qw/c tc/;
use Class::Accessor;

our (@ISA) = qw/Class::Accessor/;

__PACKAGE__->mk_accessors(qw/
    romeo
    /);

sub new {
    my ($class, $romeo) = @_;
    return bless(
        {
            romeo       =>      $romeo,
        },
        $class
    );
}

sub render_page {
    my ($self) = shift;
    $self->romeo->render_page(@_);
}

sub handle_request {
    my ($self, $romeo, @uri) = @_;
    $r->content_type('text/html');
    $romeo->template->process($self->theme . "/error.tt2", 
        {
            error   =>      'Default request handler error: load an extension with a handle_request method.'
        }
    );
}

1;
