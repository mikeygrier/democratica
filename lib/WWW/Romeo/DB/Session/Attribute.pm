package WWW::Romeo::DB::Session::Attribute;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('session_attribute');
__PACKAGE__->add_columns(
    id      =>      {
        is_auto_increment       =>      1,
        data_type               =>      'integer',
    },
    session =>      {
        data_type               =>      'integer',
        is_foreign_key          =>      1,
    },
    k       =>      {
        data_type               =>      'varchar',
        size                    =>      '255',
    },
    v       =>      {
        data_type               =>      'text',
    },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->belongs_to(session         =>          'WWW::Romeo::DB::Session');

