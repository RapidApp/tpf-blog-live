#!/usr/bin/env perl

use strict;
use warnings;


# started writing this but decided to stop and just drop the images in the scaffold.


__END__

use RapidApp::Util ':all';
use Path::Class qw/file dir/;

our $NextColor  = GREEN.BOLD;
our $ScreamNext = 0;


my $dir = dir($ARGV[0]);

-d $dir or die "Must supply valid directory of files/images as first argument";

my @files = grep { $_->isa('Path::Class::File') } $img_dir->children;

scalar(@files) > 0 or die "no files found in $img_dir";

print "\n\nFound " . scalar(@files) . " files...\n\n";


###########################################################

use Rapi::Blog;

use FindBin;
my $dir = dir("$FindBin::Bin/../")->resolve->absolute;


my $Blog = Rapi::Blog->new({ 
  site_path => "$dir", 
  fallback_builtin_scaffold => 1 
});

$Blog->to_app; # init

my $Cas = $Blog->appname->controller('SimpleCAS');


my %filemap = ();

for my $File (@files) {
  my $fn = $File->basename;
  
  exists $filemap{$fn} and die "duplicate name $fn";
  
  print "\n  -> $fn";
  
  $filemap{$fn} = $Cas->add($File);
  
  print "  ($filemap{$fn})";

}

scream(\%filemap);

