package WWW::Romeo::DB;

use base qw/DBIx::Class::Schema/;
__PACKAGE__->load_classes(qw/Session Session::Attribute User User::Attribute/);

1;
