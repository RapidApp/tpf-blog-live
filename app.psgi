# created by 'rabl.pl create'

use Rapi::Blog 1.1001;
use RapidApp::Util ':all';
use Plack::Builder;

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

my $base_appname = $app->base_appname;


# ------------------------------------
#Old site URL mapping Middleware:
my $old_url_mw = sub {
  my $app = shift;
  sub {
    my $env = shift;
    
    my ($junk,$year,$month,$title) = split(/\//,$env->{PATH_INFO},4);
    
    # strip file extension (3 or 4 characters long), if present:
    $title =~ s/\..{3}$//;
    $title =~ s/\..{4}$//;
    
    if ($year =~ /^\d{4}$/ and $month =~ /^\d{2}$/) {
      my $dt = DateTime->new( 
        year      => $year, 
        month     => $month, 
        day       => 1,
        hour      => 0,
        minute    => 0,
        second    => 0,
        time_zone => 'local'
      );
      
      my $max_dt = $dt->clone->add(months => 1);
      
      my $high = join(' ',$max_dt->ymd('-'),$max_dt->hms(':'));
      my $low  = join(' ',$dt->ymd('-'),$dt->hms(':'));
      $title =~ s/\.\W$//;
      $title =~ s/\-/\_/g;

      my $Rs = $base_appname->model('DB::Post')
        ->search_rs({ -and => [
          { ts   => { '>=' => $low    }},
          { ts   => { '<'  => $high   }},
          { name => { '='  => $title  }}
        ]});

      if(my $Match = $Rs->first) {
        return [ 307 => ['Location' => $Match->public_url], [ ] ] 
      }
    }
    
   $app->($env);
  };
}; 
# ------------------------------------


builder {
  enable $old_url_mw;
  $app;
}
   
