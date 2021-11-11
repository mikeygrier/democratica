package Praux::Url::Captcha;

@ISA = ('WWW::Romeo::Extension');

use WWW::Romeo::Extension;
use Authen::Captcha;
use Apache2::Const qw /:common/;
use Apache2::Util qw /ht_time/;
use Carp;

my $captcha = Authen::Captcha->new();

sub handle_request {
    my ($self, $romeo, @uri) = @_;

    # configure the captcha
    $captcha->data_folder($romeo->c->CAPTCHA_DATA_DIR);
    $captcha->output_folder($romeo->c->CAPTCHA_IMAGE_DIR);


    $romeo->r->no_cache(1);
    $romeo->r->content_type('image/png');

    my $file;

    if ($romeo->session->captcha_md5) {
        $file = $romeo->c->CAPTCHA_IMAGE_DIR . "/" . $romeo->session->captcha_md5 . ".png";
        unless (-e $file) {
            # new file!
            $romeo->session->captcha_md5($captcha->generate_code(6));
            $file = $romeo->c->CAPTCHA_IMAGE_DIR . "/" . $romeo->session->captcha_md5 . ".png";
        }
    } else {
        # new file!
        $romeo->session->captcha_md5($captcha->generate_code(6));
        $file = $romeo->c->CAPTCHA_IMAGE_DIR . "/" . $romeo->session->captcha_md5 . ".png";
    }

    open(CAPTCHA_IMAGE, '<', $file);
    print while <CAPTCHA_IMAGE>;
    close(CAPTCHA_IMAGE);
    return OK;
}

1;
