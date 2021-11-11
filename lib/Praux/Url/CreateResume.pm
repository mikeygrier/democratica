package Praux::Url::CreateResume;

@ISA = ('Praux::Url::Component');

use Mail::Sender;
use Praux::Url::Component;
use Apache2::Const qw/:common/;
use Apache2::Util qw/ht_time/;
use Digest::MD5 qw/md5_hex/;
use Carp;
use Praux::Util::Zimbra;
use GD::Barcode::QRcode;

$Mail::Sender::NO_X_MAILER = 1;

my $mailer = Mail::Sender->new(
    {    
        smtp        =>      'mail.mg2.org',
        from        =>      'admin@praux.com',
        headers     =>      {
            'X-Mailer'      =>      'Praux v0.05',
        }
    }
);

my $lang_hash = {
    'ne' => 'Nepali',
    'tr' => 'Turkish',
    'ki' => 'Kikuyu',
    'da' => 'Danish',
    'ug' => 'Uighur',
    'gl' => 'Galician',
    'tn' => 'Tswana',
    'ta' => 'Tamil',
    'co' => 'Corsican',
    'rw' => 'Kinyarwanda',
    'br' => 'Breton',
    'st' => 'Sotho, Southern',
    'ko' => 'Korean',
    'ak' => 'Akan',
    'ps' => 'Pushto',
    'km' => 'Central Khmer',
    'av' => 'Avaric',
    'af' => 'Afrikaans',
    'qu' => 'Quechua',
    'ti' => 'Tigrinya',
    'mt' => 'Maltese',
    'ky' => 'Kirghiz',
    'la' => 'Latin',
    'ga' => 'Irish',
    'bh' => 'Bihari languages',
    'oc' => 'Occitan (post 1500)',
    'sv' => 'Swedish',
    'it' => 'Italian',
    'hu' => 'Hungarian',
    'za' => 'Zhuang',
    'ng' => 'Ndonga',
    'dv' => 'Divehi',
    'se' => 'Northern Sami',
    'lu' => 'Luba-Katanga',
    'kv' => 'Komi',
    'jv' => 'Javanese',
    've' => 'Venda',
    'na' => 'Nauru',
    'pt' => 'Portuguese',
    'ks' => 'Kashmiri',
    'hi' => 'Hindi',
    'mh' => 'Marshallese',
    'ba' => 'Bashkir',
    'kg' => 'Kongo',
    'no' => 'Norwegian',
    'lv' => 'Latvian',
    'os' => 'Ossetian',
    'ho' => 'Hiri Motu',
    'ln' => 'Lingala',
    'id' => 'Indonesian',
    'sr' => 'Serbian',
    'si' => 'Sinhala',
    'vo' => 'Volapük',
    'ff' => 'Fulah',
    'om' => 'Oromo',
    'ab' => 'Abkhazian',
    'fi' => 'Finnish',
    'fj' => 'Fijian',
    'wo' => 'Wolof',
    'sn' => 'Shona',
    'li' => 'Limburgan',
    'sd' => 'Sindhi',
    'yi' => 'Yiddish',
    'ii' => 'Sichuan Yi',
    'gv' => 'Manx',
    'ha' => 'Hausa',
    'lg' => 'Ganda',
    'pa' => 'Panjabi',
    'sl' => 'Slovenian',
    'am' => 'Amharic',
    'mr' => 'Marathi',
    'bi' => 'Bislama',
    'ee' => 'Ewe',
    'kj' => 'Kuanyama',
    'rm' => 'Romansh',
    'dz' => 'Dzongkha',
    'kn' => 'Kannada',
    'rn' => 'Rundi',
    'eo' => 'Esperanto',
    'fy' => 'Western Frisian',
    'mn' => 'Mongolian',
    'ik' => 'Inupiaq',
    'nv' => 'Navajo',
    'gd' => 'Gaelic',
    'as' => 'Assamese',
    'ae' => 'Avestan',
    'tk' => 'Turkmen',
    'mg' => 'Malagasy',
    'su' => 'Sundanese',
    'sc' => 'Sardinian',
    'ru' => 'Russian',
    'ia' => 'Interlingua',
    'nb' => 'Bokmål',
    'cr' => 'Cree',
    'ku' => 'Kurdish',
    'vi' => 'Vietnamese',
    'az' => 'Azerbaijani',
    'lo' => 'Lao',
    'sg' => 'Sango',
    'bm' => 'Bambara',
    'aa' => 'Afar',
    'lb' => 'Luxembourgish',
    'nr' => 'Ndebele',
    'ts' => 'Tsonga',
    'kw' => 'Cornish',
    'ml' => 'Malayalam',
    'uz' => 'Uzbek',
    'ht' => 'Haitian',
    'kl' => 'Kalaallisut',
    'bs' => 'Bosnian',
    'iu' => 'Inuktitut',
    'yo' => 'Yoruba',
    'to' => 'Tonga',
    'cu' => 'Church Slavic',
    'ch' => 'Chamorro',
    'wa' => 'Walloon',
    'bg' => 'Bulgarian',
    'gu' => 'Gujarati',
    'ca' => 'Catalan',
    'pl' => 'Polish',
    'ay' => 'Aymara',
    'oj' => 'Ojibwa',
    'ty' => 'Tahitian',
    'an' => 'Aragonese',
    'uk' => 'Ukrainian',
    'es' => 'Spanish',
    'sw' => 'Swahili',
    'kr' => 'Kanuri',
    'tt' => 'Tatar',
    'fo' => 'Faroese',
    'ss' => 'Swati',
    'or' => 'Oriya',
    'sa' => 'Sanskrit',
    'xh' => 'Xhosa',
    'io' => 'Ido',
    'th' => 'Thai',
    'ie' => 'Interlingue',
    'et' => 'Estonian',
    'so' => 'Somali',
    'tl' => 'Tagalog',
    'nd' => 'Ndebele, North',
    'en' => 'English',
    'lt' => 'Lithuanian',
    'hr' => 'Croatian',
    'gn' => 'Guarani',
    'be' => 'Belarusian',
    'zu' => 'Zulu',
    'ur' => 'Urdu',
    'cv' => 'Chuvash',
    'tw' => 'Twi',
    'hz' => 'Herero',
    'ce' => 'Chechen',
    'nn' => 'Norwegian Nynorsk',
    'bn' => 'Bengali',
    'ja' => 'Japanese',
    'tg' => 'Tajik',
    'pi' => 'Pali',
    'te' => 'Telugu',
    'he' => 'Hebrew',
    'ig' => 'Igbo',
    'ar' => 'Arabic',
    'sm' => 'Samoan',
    'ny' => 'Chichewa',
    'kk' => 'Kazakh'
};

sub handle_request {
    my ($self, $romeo, @args) = @_;

    $romeo->r->no_cache(1);

    # get rid of the first argument, used to dispatch through bN
    shift(@args);

    # unpack our arguments...
    my @uri = @args;

    # sending json or html?
    $romeo->r->content_type('text/html;charset=utf-8');
    
    if ($self->instance eq "www" || $self->instance eq "ssl" || $self->instance eq "") {
        $romeo->r->content_type('text/html;charset=utf-8');
        $romeo->render_error("You can't make a resume here!  Go to an available " . $self->c->COOKIE_DOMAIN . " subdomain to make a new resume!");
        return OK;
    }
    
    if ($self->resume) {
        $romeo->r->content_type('text/html;charset=utf-8');
        $romeo->render_error("You can't make a resume here, it already exists!");
        return OK;
    }
    
    if ($self->active_user && $self->active_user->resume) {
        $romeo->r->content_type('text/html;charset=utf-8');
        $romeo->render_error("You already have a resume!");
        return OK;
    }
    
    if ($romeo->param('is_submit')) {
        # this is a submit...
        my @anticipated = qw/
            name        phone           email
            address     default_language
        /;
        my @required = qw/
            name        email           default_language
        /;

        # get everything we're anticipating getting...
        my %values = map { $_ => $romeo->param($_) || undef } @anticipated;

        if (my $error = $self->validate_input(\%values, \@required)) {
            # we're in error
            $romeo->param('error'     =>      $error);
            $self->render_page('create_resume');
        } else {
            # generate the qrcode png
            my $to_encode_string = 'http://' . $self->instance . $self->c->COOKIE_DOMAIN;
            my $qrcode_png = GD::Barcode::QRcode->new(
                $to_encode_string,
                {
                    Ecc => 'L',
                    Version => 6,
                    ModuleSize => 6,
                }
            )->plot->png;
            
            # do the create
            my $resume;
            eval { 
                $resume = $self->schema->resultset('Resume')->create(
                    {   
                        name => $values{name},
                        email => $values{email},
                        phone => $values{phone},
                        address => $values{address},
                        default_language => $values{default_language},
                        default_theme => $self->global_theme_by_name($self->active_user->provisioner->default('theme'))->id,
                        instance => $self->instance,
                        praux_user => $self->active_user,
                        qrcode_png => $qrcode_png,
                    }
                );
            };

            if (my $error = $@) {
                $romeo->param('error' => 'creating resume: ' . $error);
                $self->render_page('create_resume');
                return OK;
            }

            # much better!
            my $resume_yaml = $self->active_user->provisioner->default('resume_template');
            
            # now import this awesome into the resume!
            $self->import_yaml_resume($resume_yaml, $self->instance);
            if (my $error = $@) {
                $romeo->param('error' =>      'Unknown error: ' . $error);
                $self->render_page('create_resume');
            } else {
                $self->log_action({
                    action => __PACKAGE__,
                    resume => $self->resume,
                    instance => $self->instance,
                    acting_user => $self->active_user->id,
                });
                
                # at Vera's suggestion.. mail masking by default
                my $zimbra = Praux::Util::Zimbra->new( resume => $resume );
                $zimbra->enable_mailmask;
                $resume->praux_user->preference('com.praux.showmailmask', 1);
                $resume->praux_user->preference('com.praux.publish_resume', 1);
                
                # do the redirect here!
                $romeo->r->headers_out->set(Location => '/edit/');
                return REDIRECT;
            }
        }
    } else {
        $self->render_page('create_resume');
    }
    return OK;
}

sub validate_input {
    my ($self, $values, $required) = @_;

    # now check to make sure we have all our crap..
    foreach my $var (@$required) {
        unless (defined $values->{$var}) {
            return "Required attribute $var not found!";
        }
    }  

    unless ($values->{email} =~ /[\w\.\%-]+\@[\w\.-]+\.[A-Za-z]{2,4}/o) {
        # invalid email address!
        return "Malformed e-mail address! ($values->{email})";
    }

    return undef;
}



sub time {
    my ($self) = @_;
    return time;
}

sub _rand_md5hex {
    my ($password) = @_;
    $password = substr($_[0], sprintf('%d', rand(length($password))), 4) if ($_[0]);
    my ($r1, $r2, $r3, $r4);
    $r1 = sprintf('%d2', rand(100));
    $r2 = rand($r1);
    $r3 = sprintf('%d2', rand(122580 + $r2));
    $r4 = rand($r3 + $r2);
    return md5_hex("$r1$r2$r3$password$r4");
}

1;
