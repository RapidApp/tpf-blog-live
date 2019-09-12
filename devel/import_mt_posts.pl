#!/usr/bin/env perl

use strict;
use warnings;

use RapidApp::Util ':all';
use Path::Class qw/file dir/;

our $NextColor  = GREEN.BOLD;
our $ScreamNext = 0;


my $fn = $ARGV[0] or die "must supply filename as first argument.\n";

my $File = file($fn);
-f $File or die "Bad filename.\n";

my %users = ();

# ------
# optional second arg user file
if(my $ufn = $ARGV[1]) {

  my $File = file($ufn);
  -f $File or die "Bad user filename.\n";

  for my $chunk ( grep { $_ =~ /\t/ } split(/\n\t/,scalar $File->slurp)) {
    my @lines = split(/\n/,$chunk);

    my ($status,$info) = split(/\s+/,(shift @lines),2);
    my ($username,$display) = split(/\t/,$info);
    
    die "Bad status '$status'" unless ($status eq 'Enabled' || $status eq 'Disabled');
    
    my $data = {
      enabled  => $status eq 'Enabled' ? 1 : 0,
      username => $username,
      display  => $display,
      roles    => \@lines
    };
    
    die "duplicate username key '$username'" if ($users{$username});
    
    # index by both:
    $users{$username} = $data;
    $users{$display}  = $data unless ($users{$display});
    
  }
}
# -------



my @chunks = split(/\n-{8}\n/,scalar $File->slurp);
print scalar(@chunks) . " chunks\n";


my @posts = map { &_parse_chunk($_) } @chunks;
print scalar(@posts) . " posts parsed\n\n";

#&_dump_posts_infos(\@posts); exit;
#print scalar(@chunks) . " chunks\n\n";


###########################################################

use Rapi::Blog;

use FindBin;
my $dir = dir("$FindBin::Bin/../")->resolve->absolute;


my $Blog = Rapi::Blog->new({ 
  site_path => "$dir", 
  fallback_builtin_scaffold => 1 
});

$Blog->to_app; # init


my $Rs = $Blog->base_appname->model('DB::Post');
my $uRs = $Blog->base_appname->model('DB::User');
my $cRs = $Blog->base_appname->model('DB::Comment');

# must pre-create authors to prevent the chance of them being seen on a comment 
# before created as an author
print "\n Creating authors ";
for my $post (@posts) {

  my $author = $post->{_meta}{author} or next;
  
  my $username = lc($author->{username});
  $username =~ s/\s//g;
  $username =~ s/\W/_/g;

  my $User = $Blog->base_appname->model('DB::User')
    ->find_or_create({
      username => $username,
      full_name => $author->{display} || $username,
      author => 1, admin => 0, comment => 1
    },{ key => 'username_unique' }) and print '.';
}

print "\n\n";

for my $post (@posts) {
  print "\n";
  my $name = $post->{BASENAME} or next;
  
  print "  $name  ...  ";
  
  my $title = $post->{TITLE} || $name;
  my $body = $post->{BODY} or next;

  my $ts = $post->{_meta}{ts} or next;
  my $author = $post->{_meta}{author} or next;
  
  my $username = lc($author->{username});
  $username =~ s/\s//g;
  $username =~ s/\W/_/g;
  
  my $User = $uRs->search_rs({ 'me.username' => $username })->first or die "user not exist";

  my $uid = $User->id;

  my $packet = {
    name => $name,
    title => $title,
    author_id  => $uid,
    creator_id => $uid,
    updater_id => $uid,
    body => $body,
    published => 1,
    ts => $ts
  };
  
  
  if (my $cats = $post->{CATEGORY}) {
    $cats = [$cats] unless (ref $cats);
    unshift @$cats, $post->{'PRIMARY CATEGORY'} if ($post->{'PRIMARY CATEGORY'});
    @$cats = uniq(@$cats);
    
    $Blog->base_appname->model('DB::Category')->find_or_create({ name => $_ }) for (@$cats);
    $packet->{post_categories} = [ map {{ category_name => $_ }} @$cats ];
  }
  
  if (my $kw = $post->{_meta}{keywords}) {
    s/\s/-/g for (@$kw);
    $packet->{body} .= "\n\n" . join(' ',map { '#'.lc($_) } @$kw); 
  }
  
  my $Post;
  my $post_id;
  try {
    $Post = $Rs->create($packet) and print "created";
    $post_id = $Post->get_column('id');
  }
  catch { warn RED.BOLD . $_ . CLEAR };
  
  next unless $post_id;
  
  for my $comment (@{$post->{_meta}{comments} || []}) {
    my $User = &_get_comment_author($comment) or die "failed to get comment author";
    my $uid = $User->get_column('id');
    $cRs->create({
      user_id => $uid,
      post_id => $post_id,
      ts => $comment->{_meta}{ts},
      body => $comment->{CommentBody}
    }) and print " .";
  }



}



########################################################################################################
########################################################################################################
########################################################################################################
########################################################################################################
      exit; #############################################################################################
########################################################################################################
########################################################################################################
########################################################################################################
########################################################################################################



sub _get_comment_author {
  my $comment = shift;
  
  my $author = $comment->{AUTHOR} or return undef;
  
  my $username = $author;
  $username = lc($username);
  $username =~ s/\s//g;
  $username =~ s/\W/_/g;
  
  my $User = $uRs->search_rs({ 'me.full_name' => $author })->first
    || $uRs->search_rs({ 'me.username' => $username })->first;
  
  unless($User) {

    try {
    
      $User = $uRs
        ->find_or_create({
          username => $username,
          full_name => $author,
          email => $comment->{EMAIL},
          author => 0, admin => 0, comment => 1
        },{ key => 'username_unique' })
    }
    catch { warn RED . $_ . CLEAR };
      
  }
  
  $User
}



sub _parse_chunk {
  my $chunk = shift;
  my $comment_chunk = shift;
  my $data = {};
  
  my @lines = split(/\r?\n/,$chunk);
  while (scalar(@lines) > 0) {
    my $kv = &_readnext_key_value(\@lines) or next;
    my ($k,$v) = @$kv;
    die "bad/missing key" unless $k;
    
    $v =~ s/^\s+// unless (ref $v); # prune leading whitespace
    
    if ($data->{$k}) {
      $data->{$k} = [$data->{$k}] unless (ref($data->{$k}));
      push @{$data->{$k}}, $v;
    }
    else {
      $data->{$k} = $v;
    }
    
    # special handling for comments, DATE is the last attr, the rest is the comment body, 
    # simulate ML format for next pass (fwiw, this is terrible, but i'm lazy)
    if ($comment_chunk && $k eq 'DATE') {
      pop @lines while (! $lines[-1] || $lines[-1] eq '-----');
      @lines = ('-----','CommentBody:',@lines)
    }


  }
  
  &_meta_normalize($data,$comment_chunk);
}


sub _meta_normalize {
  my $data = shift;
  my $comment_chunk = shift;
  
  my $meta = $data->{_meta} = {};

  if ($data->{KEYWORDS}) {
    my @kw = ();
    for my $line (split(/\n/,$data->{KEYWORDS})) {
      next if (!$line or ($line =~ /^\s*$/) or $line eq '-----');
      push @kw, split(/\s*,\s*/,$line);
    };
    
    $meta->{keywords} = \@kw if (scalar(@kw) > 0);
  }
  
  
  if (my $comments = $data->{COMMENT}) {
    $comments = [$comments] unless (ref($comments));
    $meta->{comments} = [ map { &_parse_chunk($_,1) } @$comments ];
  }
  
  if($data->{DATE}) {
    my $dt = &_parse_timestamp_dt($data->{DATE});
    $meta->{ts} = join(' ',$dt->ymd('-'),$dt->hms(':'));
  }
  
  unless($comment_chunk) {
    if($data->{AUTHOR}) {
      if(my $user = $users{$data->{AUTHOR}}) {
        $meta->{author} = $user;
      }
    }
  }
  
  
  $data
}



sub _readnext_key_value {
  my $lines = shift;
  die "expected ArrayRef" unless (ref($lines) && ref($lines) eq 'ARRAY');
  
  my $next = &_shift_next($lines) or return undef;
  return &_readnext_ml_key_value($lines) if ($next eq '-----');
  
  my ($k,$v) = split(/\:/,$next,2);
  
  return [$k,$v];
}



sub _readnext_ml_key_value {
  my $lines = shift;
  
  local $NextColor = MAGENTA.BOLD;
  
  my $next = (&_shift_next($lines) || &_shift_next($lines)) or return undef;
  
  my ($k,$v) = split(/\:/,$next,2);
  
  die "expected multi-line data, got '$v'" if ($v);
  
  while (! &_at_multiline_end($lines)) {
    $next = &_shift_next($lines);
    $v .= "$next\n";
  }
  
  return [$k,$v];
}


sub _at_multiline_end {
  my $lines = shift;
  return 1 if (scalar(@$lines) == 0);
  return 0 unless ($lines->[0] eq '-----');
  my $peek = &_peek_next_non_blank($lines,1);
  return 1 if ($peek =~ /^[A-Z\s]+\:/);
  return 0;
}



sub _shift_next {
  my $lines = shift;
  my $next = shift @$lines;
  scream_color($NextColor,$next) if ($ScreamNext);
  $next;
}


sub _peek_next_non_blank {
  my $lines = shift;
  my $ndx   = shift || 0;
  
  my $i = 0;
  for (@$lines) {
    next if($i++ < $ndx);
    return $_ if ($_ && !($_ =~ /^\s*$/));
  }
  
  return ''
}



sub _parse_timestamp_dt {
  my $string = shift;
  
  my ($date,$time,$ap) = split(/\s/,$string,3);
  my ($mon,$day,$year) = split(/\//,$date,3);
  my ($hour,$min,$sec) = split(/\:/,$time,3);
  $hour = $hour + 12 if (lc($ap) eq 'pm' && $hour < 12);
  
  require DateTime;
  DateTime->new(
    year => $year, month  => $mon, day    => $day,
    hour => $hour, minute => $min, second => $sec
  )
}



sub _dump_posts_infos {
  my $posts = shift;

  my %key_counts = ();
  my @infos = ();
  for (@$posts) {
    my $info = {};
    for my $k (keys %$_) {
      $key_counts{$k}++;
      my $v = $_->{$k};
      
      if(my $type = ref($v)) {
        $info->{$k} = $type eq 'ARRAY' ? 'ARRAY('.scalar(@$v).')' : $v;
      }
      else {
        my @lines = split(/\n/,$v);
        my $num = scalar(@lines);
        if($num > 1) {
          $info->{$k} = "MULTI-LINE($num lines)";
        }
        else {
          $info->{$k} = $v
        }
      }
    }
    push @infos, $info;

  }

  $Data::Dumper::Maxdepth = 8;

  #scream(\@posts);
  scream(\@infos);


  #scream_color(BLUE.BOLD,[ map { $_->{COMMENT} } @posts ]);

  scream_color(MAGENTA,\%key_counts);
}
