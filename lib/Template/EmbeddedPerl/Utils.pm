package Template::EmbeddedPerl::Utils;

use warnings;
use strict;
use Exporter 'import'; 
use URI::Escape ();

our @EXPORT_OK = qw(
  normalize_linefeeds
  uri_escape
  escape_javascript
  generate_error_message
);

# uri_escape is a function from URI::Escape
# it is used to escape the uri string.
# uri_escape('http://www.google.com') => 'http%3A%2F%2Fwww.google.com'

sub uri_escape {
  my ($string) = @_;
  return URI::Escape::uri_escape($string);
}

# normalized the line endings to \n from mac and windows format.

sub normalize_linefeeds {
  my ($template) = @_;
  $template =~ s/\r\n/\n/g;
  $template =~ s/\r/\n/g;
  return $template;
}

my %JS_ESCAPE_MAP = (
  '\\' => '\\\\',
  '</' => '<\/',
  "\r\n" => '\n',
  "\3342\2200\2250" => '\x{3342}\x{2200}\x{2250}',
  "\3342\2200\2251" => '\x{3342}\x{2200}\x{2251}',
  "\n" => '\n',
  "\r" => '\n',
  '"' => '\"',
  "'" => "\\'"
);

sub escape_javascript {
  my ($javascript) = @_; 
  if ($javascript) {
    my $pattern = join '|', map quotemeta, keys %JS_ESCAPE_MAP;
    my $result = $javascript =~ s/($pattern)/$JS_ESCAPE_MAP{$1}/egr;
    return $result;
  } else {
      return "";
  }
}

sub generate_error_message {
  my ($msg, $template, $source) = @_;

  $source = $source ? "$source" : 'unknown';

  my @files;
  push @files, [$1, $2, $3, $msg] while $msg =~ /^(.+?) at\s+(.+?)\s+line\s+(\d+)/gm;

  my $text = '';
  foreach my $file (@files) {
    my ($msg, $file, $line, $extra) = @$file; 
    if($file !~ m/eval/) {
      $text .= $extra;
      next;
    }
    $text .= "$msg at $source line $line\n\n";

    $line--;
    my $start = $line -1 >= 0 ? $line -1 : 0;
    my $end = $line + 1 < scalar(@$template) ? $line + 1 : scalar(@$template) - 1;
    for my $i ($start..$end) {
      $text .= "@{[ $i+1 ]}: $template->[$i]\n";
    }
    $text .= "\n";
  }

  return "$text\n";
}

1;
