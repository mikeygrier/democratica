package Praux::DB::Resume::Collection;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_resume_collection');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    uuid => {
        data_type => 'varchar',
        is_nullable => 1,
        size => 64,
    },
    edit_key => {
        data_type => 'varchar',
        size => 128,
    },
    name => {
        data_type => 'varchar',
        size => 255,
    },
    create_time => {
        data_type => 'integer',
    },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->has_many(members => 'Praux::DB::Resume::Collection::Member');

# add a resume to a collection
sub add {
    my ($self, $resume) = @_;
    if (ref($resume)) {
        $self->members->create(
            {
                resume => $resume->id,
                collection => $self->id,
            }
        );
        return 1;
    }
    return undef;
}

# remove a resume from a collection
sub remove {
    my ($self, $resume) = @_;
    if (ref($resume)) {
        $member = $self->members->search({
            resume => $resume->id,
            collection => $self->id,
        })->first;
        $member->delete;
        return 1;
    }
    return undef;
}

# this just gets the resumes ;)
sub resumes {
    my ($self) = @_;
    my @resumes;
    foreach my $member ($self->members) {
        push(@resumes, $member->resume);
    }
    return @resumes;
}

# make sure we keep create time up to date..
sub insert {
    my ($self, @args) = @_;
    $self->create_time(time);
    
    # no uuid?  we make one here.
    $self->uuid($self->new_uuid) unless $self->uuid;
    $self->next::method(@args);
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
    
    # index on uuid
    $sqlt_table->add_index(
        name => 'uuid_idx', 
        fields => ['uuid'],
    );
    
    # index on name
    $sqlt_table->add_index(
        name => 'name_idx', 
        fields => ['name'],
    );
}

1;
