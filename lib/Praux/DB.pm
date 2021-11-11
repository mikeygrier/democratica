package Praux::DB;

use base qw/DBIx::Class::Schema/;

# we're now versioning our schemas -- must remember to update this when we increment
our $VERSION = 0.055;

# import our goodies
__PACKAGE__->load_classes();

# versioning!
__PACKAGE__->load_components(qw/Schema::Versioned/);
__PACKAGE__->upgrade_directory('/usr/local/praux/schema/upgrades/');
__PACKAGE__->backup_directory('/usr/local/praux/schema/backups/');

1;
