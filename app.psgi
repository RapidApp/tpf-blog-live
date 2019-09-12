# created by 'rabl.pl create'

use Rapi::Blog 1.1001;
use RapidApp::Util ':all';

use Path::Class qw/file dir/;
my $dir = file($0)->parent->stringify;

# ---- 
# New: add quick and dirty support for importing additional local Rai::Blog config from YAML file.
# This is being done in order to separate SMTP configs which may include credentials
use YAML::XS 0.64 'LoadFile';
my $local_cfg = do {
  my $fn = 'local_rabl_cfg.yml';
  my $data = {};
  my $File = file($dirt,$fn);
  if(-f $File) {
    $data = LoadFile( $File ) || {};
    die "Bad '$fn' file -- did not parse into required HashRef format" unless (ref($data)||'' eq 'HASH');
  }
  $data
};
# ----


my $app = Rapi::Blog->new({
  site_path     => $dir,
  scaffold_path => "$dir/scaffold",
  
  ## when no custom smtp_confit is supplied, the app defaults to use sendmail on the local system
  #smtp_config => {},
  
  ## FOr testing, override_email_recipient can be set to redirect all mails to a single address
  #override_email_recipient => 'any_address@whatever.com',
  
  # If a local config file exists, it can/will override any settings above
  %$local_cfg
});

# Plack/PSGI app:
$app->to_app
