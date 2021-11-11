package Praux::DB::Resume::ContentItem::Comment;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_resume_content_item_comment');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    content_item => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    content_block => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    section => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },   
    resume => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    owner => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    submitter => {
        data_type => 'integer',
        is_foreign_key => 1,
        is_numeric => 1,
    },
    marked_read => {
        data_type => 'integer',
        is_numeric => 1,
        default_value => '0',
    },
    create_time => {
        data_type => 'integer',
        is_numeric => 1,
        default_value => 0,
    },
    comment => {
        data_type => 'text',
    }
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(owner => 'Praux::DB::User');
__PACKAGE__->belongs_to(submitter => 'Praux::DB::User');
__PACKAGE__->belongs_to(content_item => 'Praux::DB::Resume::ContentItem');
__PACKAGE__->might_have(content_block => 'Praux::DB::Resume::ContentBlock');
__PACKAGE__->might_have(section => 'Praux::DB::Resume::Section');
__PACKAGE__->might_have(resume => 'Praux::DB::Resume');

sub insert {
    my ($self, @args) = @_;
    $self->create_time(time);
    $self->next::method(@args);
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
}

sub type {
    my ($self) = @_;
    foreach my $meth (qw/content_item content_block section resume/) {
        if ($self->$meth) {
            return $meth;
        }
    }
    return undef;
}

1;
