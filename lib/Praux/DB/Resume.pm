package Praux::DB::Resume;

use YAML::Syck;
use XML::Simple;
use JSON;

my $json = new JSON;

use base qw/DBIx::Class Praux/;
__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->table('praux_resume');

__PACKAGE__->add_columns(
    id => {
        is_auto_increment => 1,
        data_type => 'integer',
        is_numeric => 1,
    },
    address => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    email => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    name => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    phone => {
        data_type => 'varchar',
        size => 64,
        is_nullable => 1,
    },
    instance => {
        data_type => 'varchar',
        size => 255,
    },
    tokens => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    default_language => {
        data_type => 'varchar',
        size => 32,
        is_nullable => 1,
    },
    default_theme => {
        data_type => 'integer',
    },
    score => {
        data_type => 'integer',
        is_numeric => 1,
        default_value => 0,
    },
    create_time => {
        data_type => 'integer',
        is_numeric => 1,
        default_value => 0,
    },
    modify_time => {
        data_type => 'integer',
        is_numeric => 1,
        default_value => 0,
    },
    completeness => {
        data_type => 'integer',
        is_numeric => 1,
        default_value => 0,
    },
    summary => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    hit_count => {
        data_type => 'integer',
        is_numeric => 1,
        default_value => 0,
    },
    qrcode_png => {
        data_type => 'blob',
        is_nullable => 1,
    },
    passphrase => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    uuid => {
        data_type => 'varchar',
        size => 255,
        is_nullable => 1,
    },
    praux_user => {
        data_type => 'integer',
        is_numeric => 1,
        is_foreign_key => 1,
    },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(praux_user => 'Praux::DB::User');
__PACKAGE__->has_many(sections => 'Praux::DB::Resume::Section');
__PACKAGE__->has_many(votes => 'Praux::DB::User::Vote', 'resume');
__PACKAGE__->has_many(views => 'Praux::DB::Resume::View', 'resume');
__PACKAGE__->has_many(comments => 'Praux::DB::Resume::ContentItem::Comment', 'resume');
__PACKAGE__->has_many(content_blocks => 'Praux::DB::Resume::ContentBlock', 'resume', { cascade_delete => 0 });
__PACKAGE__->has_many(content_items => 'Praux::DB::Resume::ContentItem', 'resume', { cascade_delete => 0 });
__PACKAGE__->has_many(suggestions => 'Praux::DB::Resume::ContentItem::Suggestion', 'resume', { cascade_delete => 0 });
__PACKAGE__->has_many(delegates => 'Praux::DB::Resume::Delegate');
__PACKAGE__->has_many(changes => 'Praux::DB::Log', 'resume', { cascade_delete => 0, is_foreign_key_constraint => 0 });
__PACKAGE__->has_many(hits => 'Praux::DB::HitLog', 'resume', { cascade_delete => 0, is_foreign_key_constraint => 0 });
__PACKAGE__->has_many(themes => 'Praux::DB::Resume::Theme', 'resume');

# many to many for categories..
__PACKAGE__->has_many(resume_categories => 'Praux::DB::Resume::ResumeCategory', 'resume');
__PACKAGE__->many_to_many(categories => 'resume_categories', 'category');

# recent comments.
sub recent_comments_paged {
    my ($self, $page, $rows) = @_;
    $rows = 15 unless $rows;
    
    return $self->comments->search({},
        {
            order_by => "create_time DESC",
            rows => $rows,
            page => $page ? $page : 1,
        }
    );
}

# poor naming convention band-aid
sub owner {
    my ($self) = @_;
    return $self->praux_user;
}

# i'll just do this fucking relationship myself
sub default_theme_object {
    my ($self) = @_;
    
    return $self->schema->resultset('Resume::Theme')->single({ id => $self->default_theme });
}

sub languages {
    my ($self) = @_;
    # get the languages
    my $lh = {};
    foreach my $ci ($self->content_items) {
        $lh->{$ci->language}++;
    }
    return keys %$lh;
}

sub is_in_language {
    my ($self, $lang) = @_;
    
    # get the languages
    my $lh = {};
    foreach my $ci ($self->content_items) {
        $lh->{$ci->language}++;
    }
    
    if (exists($lh->{lc($lang)})) {
        return 1;
    }
    
    return undef;
}

sub insert {
    my ($self, @args) = @_;
    $self->create_time(time);
    $self->modify_time(time);
    # add a UUID if we don't have one yet
    $self->uuid($self->new_uuid) unless $self->uuid;  
    $self->next::method(@args);
}

# resumes can have gravatars too ;)
sub gravatar {
    my ($self) = @_;
    return Praux::gravatar($self->email);
}

sub last_changed_date {
    my ($self) = @_;
    return $self->changes(undef, { order_by => 'create_time DESC' })->first->create_time;
}

sub url {
    my ($self) = @_;
    return 'http://' . $self->instance . $self->c->COOKIE_DOMAIN;
}

sub title_url {
    my ($self) = @_;
    my $title = $self->recent_title;
    if ($title eq "Editor In Chief" or $title eq "An Excellent Candidate") {
        return $self->url . "/resume.html";
    }
    return 'http://' . $self->instance . $self->c->COOKIE_DOMAIN . "/" . join('-', map { lc($_) } split(/\s+/, $self->recent_title)) . ".html";
}

sub sorted_sections {
    my ($self) = @_;
    return $self->sections->search({}, {order_by => ['sort_order ASC']});
}

sub summarize_changes {
    my ($self) = @_;
    # CONFIG we might make this a configuration variable later
    my $chunk_time = 300; # 5 minutes right now..
    my $chunks = [];
    my ($chunk, $start_time) = ([], 0);
    
    # get the changes that happened in the last 2 weeks!
    foreach my $change ($self->changes->search({ create_time => { '>', (time() - 1209600) }}, { order_by => 'create_time', })->all) {
        if (!$start_time && !scalar(@$chunk)) {
            $start_time = $change->create_time;
            push(@$chunk, $change);
            next;
        } elsif (!$start_time && scalar(@$chunk)) {
            $start_time = $chunk->[0]->create_time;
        }
        
        if ($start_time + 300 < $change->create_time) {
            # time to start a new chunk
            $start_time = 0;
            push(@$chunks, $chunk);
            $chunk = [$change];
        } else {
            push(@$chunk, $change);
        }
    }
    
    # get the straglers ;)
    push(@$chunks, $chunk) if scalar(@$chunk);

    my @summaries = ();
    foreach my $chunk (@$chunks) {
        if (scalar(@$chunk)) {
            $summary = {
                description => $self->textify_changes($chunk),
                title => "Changes Between " . $self->pretty_date($chunk->[0]->create_time) . " and " . $self->pretty_date($chunk->[$#{$chunk}]->create_time),
                date => $chunk->[0]->create_time,
            };
            push(@summaries, $summary);
        }
    }
    
    return(reverse @summaries);
}

sub percent_complete {
    my ($self) = @_;
    
    # if the cherry hasn't been popped, let's just return 0
    return 0 unless $self->changes->search({action => 'Praux::Url::JSON::EditContentItem'})->count;
    
    my $pct = (4 * (12 - $self->tip_blocks_left));
    $pct += 12 if $self->created_objective;
    $pct += 12 if $self->created_jobs;
    $pct += (4 * ($self->jobs_created > 3 ? 3 : $self->jobs_created));
    $pct += 16 if $self->created_education;
    $pct += $self->score;
    $pct = 100 if $pct >= 80;
    return $pct;
}

sub created_education {
    my ($self) = @_;
    foreach my $block ($self->content_blocks->search( { format => 'section_header' })->all) {
        if ($block->visible_item($self->default_language) && $block->visible_item($self->default_language)->body =~ /(?:education|college|university|school)/i) {
            return 1;
        }
    }
    return undef;
}

sub created_jobs {
    my ($self) = @_;
    foreach my $block ($self->content_blocks->search( { format => 'section_header' })->all) {
        if ($block->visible_item($self->default_language) && $block->visible_item($self->default_language)->body =~ /(?:employment|jobs|work experience|work)/i) {
            return 1;
        }
    }
    return undef;
}

sub created_objective {
    my ($self) = @_;
    foreach my $block ($self->content_blocks->search( { format => 'section_header' })->all) {
        if ($block->visible_item($self->default_language) && $block->visible_item($self->default_language)->body =~ /(:?objective|overview)/i) {
            return 1;
        }
    }
    return undef;
}

sub courses_created {
    my ($self) = @_;
    return $self->content_blocks->search({ format => 'course' })->count;
}

sub projects_created {
    my ($self) = @_;
    return $self->content_blocks->search({ format => 'projects' })->count;
}

sub sections_created {
    my ($self) = @_;
    return $self->content_blocks->search({ format => 'section_header' })->count;
}

sub jobs_created {
    my ($self) = @_;
    return $self->content_blocks->search({ format => 'job' })->count;
}

sub tip_blocks_left {
    my ($self) = @_;
    my $count = 0;
    foreach my $block ($self->content_blocks->search({ format => 'generic' })->all) {
        if ($block->visible_item($self->default_language) && $block->visible_item($self->default_language)->body =~ /PRAUX TIP/) {
            $count++;
        }
    }
    return $count;
}

sub recent_title {
    my ($self) = @_;
    
    my $recent_title = "An Excellent Candidate";
    # derive a working job title..
    foreach my $section ($self->sections->search({ format => 'job' })) {
        next unless $section->content_blocks->search({ format => 'job' })->first;
        my $vi = $section->content_blocks->search({ format => 'job' })->first->visible_item('en');
        next unless $vi;
        $recent_title = $vi->title;
        last;
    }
    
    $recent_title =~ s/[^\w\s\,\.]+//g;
    $recent_title =~ s/[\.\,\s]+$//g;
    
    return $recent_title;
}

sub textify_changes {
    my ($self, $changes) = @_;
    my $change_text;
    my $change_time;
    
    foreach my $change (sort {$a->create_time <=> $b->create_time} @$changes) {
        if (!$change_time || ($change->create_time != $change_time)) {
            $change_text .= "\n-------------------------------------\n";
            $change_text .= "Changes On " . $self->pretty_date($change->create_time) . "\n";
            $change_text .= "-------------------------------------\n";
            $change_time = $change->create_time;
        }
        
        $change_text .= " *  " . $change->action . "\n";
        
        if ($change->action eq "Praux::Url::JSON::EditContentItem" || $change->action eq "Praux::Url::JSON::AddContentItem") {
            my $nv = Load($change->new_value);
            if (!$change->old_value || ($change->new_value eq $change->old_value)) {
                # just talk about the new value.. dont have to do differences..
                $change_text .= "    Created new content item in language $nv->{language}.\n";
                for (qw/date_range organization locality role instructor title body/) {
                    if (defined($nv->{$_})) {
                        if ($change->content_block->format eq "section_header") {
                            $change_text .= "     *  Section Header Added\n";
                        } else {
                            $change_text .= "     *  Field Added: $_\n";
                        }
                        $change_text .= "     ++ New Value: $nv->{$_}\n";
                    }
                }
            } else {
                # talk about what changed
                my $ov = Load($change->old_value);
                $change_text .= "    Edited existing content item in language $nv->{language}.\n";
                for (qw/date_range organization locality role instructor title body/) {
                    if ($nv->{$_} ne $ov->{$_}) {
                        if ($change->content_block->format eq "section_header") {
                            $change_text .= "     *  Section Header Changed\n";
                        } else {
                            $change_text .= "     *  Field Changed: $_\n";
                        }
                        $change_text .= "     -- Old Value: $ov->{$_}\n";
                        $change_text .= "     ++ New Value: $nv->{$_}\n";
                    }
                }
            }
        } elsif ($change->action eq "Praux::Url::JSON::AddSection") {
            # print the title in the default language!
            if ($change->section->header_cb) {
                $change_text .= "    Added new section: '" . $change->section->header_cb->visible_item($change->resume->default_language)->body . "'\n";
            } else {
                $change_text .= "    Section created here, has since perished.  May it rest in peace.\n";
            }
        }
        $change_text .= "\n";
    }
    
    return $change_text;
}

sub random_excerpts {
    my ($self, $lang) = @_;
    
    # default a language!
    $lang = $self->default_language || 'en' unless $lang;
    
    my ($last, $overview, $objective, @random);
    foreach my $section ($self->sorted_sections) {
        # extract this section's content blocks!
        my @blx = $section->sorted_content_blocks;
        for (my $i = 0; $i < scalar(@blx); $i++) {
            my $cb = $blx[$i];
            unless ($overview && $objective) {
                if ($cb->format eq "section_header") {
                    my $vi = $cb->visible_item($lang);
                    
                    # ohhhkay.. skip if there's no visible item
                    next unless $vi;
                    
                    my $lc_body = lc($vi->body);
                    if ($lc_body eq "overview") {
                        # get the overview.. (note i is incremented)
                        
                        # for these freak cases...
                        my $ncb = $blx[++$i];
                        next unless $ncb;
                        my $vi = $ncb->visible_item($lang);
                        next unless $vi;
                        
                        # actually populate!
                        $overview = $self->truncate($vi->body, 100, 1);
                        next;
                    } elsif ($lc_body eq "objective") {
                        # get the objective (note i increment i)
                        
                        # for these freak cases...
                        my $ncb = $blx[++$i];
                        next unless $ncb;
                        my $vi = $ncb->visible_item($lang);
                        next unless $vi;
                        
                        # actually populate!
                        $objective = $self->truncate($vi->body, 100, 1);
                        
                        next;
                    }
                }
            }
            
            my $vi = $cb->visible_item($lang);
            
            # skip if there's no visible item
            next unless $vi;
            
            # this is a candidate for random... skip PRAUX TIP blocks
            next if $vi->body =~ /PRAUX TIP/;
            
            unless (int(rand(10)) % 3) {
                if (scalar(@random) < 15) {
                    next if $cb->format eq "section_header";
                    my $body = $vi->body;
                    push(@random, $self->truncate($body, 80, 1)) if $body;
                } else {
                    $last = 1;
                    last;
                }
            }
        }
        
        # outer last!
        last if $last;
    }
    
    my $excerpts;
    unless ($overview =~ /PRAUX TIP/ || !$overview) {
        $excerpts = "$overview - ";
    }
    
    unless ($objective =~ /PRAUX TIP/ || !$objective) {
        $excerpts .= "$objective";
    }
    
    # append randomly!
    foreach my $rand (@random) {
        if (length($excerpts) < 250) {
            $excerpts .= " " . $rand;
        } else {
            last;
        }
    }
    
    # hard truncate!
    if (length($excerpts) > 255) {
        # hard truncate!
        $excerpts = $self->truncate($excerpts, 240, 1);
    }
    
    $excerpts = "Insufficient content for summary calculation" unless $excerpts;
    
    return $excerpts . " ... ";
}

# to-data in prep for serialization.. was gunna use export/import but thats 
# gunna collide with perly things.
sub to_data {
    my ($self) = @_;
    my $export = {
        sections => [],
        instance => $self->instance,
        praux_user => $self->praux_user->id,
    };
    
    foreach my $method (qw/address email name phone/) {
        if (defined($self->$method)) {
            $export->{$method} = $self->$method;
        }
    }
    
    foreach my $section ($self->sections) {
        push (@{$export->{sections}}, $section->to_data);
    }
    
    return $export;
}

# text serialization needs to be done..  all the other serializations need to handle view too.. ;P
sub serialize_text {
    my ($self, $view, $lang) = @_;

    # the header!
    my $text = $self->name . "\n";
    $text .= $self->email . "\n";
    $text .= $self->address . "\n" if $self->address;
    $text .= $self->phone . "\n" if $self->phone;
    $text .= "\n";
    
    foreach my $section ($self->sorted_sections) {
        if ($self->has_view($section, $view)) {
            
        }
    }
}

sub serialize_json {
    my ($self) = @_;
    return $json->encode($self->to_data);
}

sub serialize_yaml {
    my ($self) = @_;
    return Dump($self->to_data);
}

sub serialize_xml {
    my ($self) = @_;
    return XMLout($self->to_data);
}

sub clear {
    my ($self) = @_;
    foreach my $section ($self->sections) {
        $section->delete;
    }
}

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->extra(
        mysql_table_type => 'InnoDB',
        mysql_charset => 'utf8',
    );
    
    $sqlt_table->add_index(
        name => 'instance_idx',
        fields => ['instance'],
    );
    
    $sqlt_table->add_index(
        name => 'name_idx',
        fields => ['name'],
    );
    
    $sqlt_table->add_index(
        name => 'email_idx',
        fields => ['email'],
    );
    
    $sqlt_table->add_index(
        name => 'address_idx',
        fields => ['address'],
    );
    
    $sqlt_table->add_index(
        name => 'tokens',
        fields => ['tokens'],
    );
    
    $sqlt_table->add_index(
        name => 'phone_idx',
        fields => ['phone'],
    );
    
    $sqlt_table->add_index(
        name => 'uuid_idx',
        fields => ['uuid'],
    );
}

1;
