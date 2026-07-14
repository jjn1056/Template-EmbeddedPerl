package Template::EmbeddedPerl::Utils;

use warnings;
use strict;
use Exporter 'import'; 
use URI::Escape ();
use JSON::MaybeXS;

our @EXPORT_OK = qw(
  normalize_linefeeds
  uri_escape
  escape_javascript
  decorate_render_error
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

# Create a JSON encoder
my $json = JSON::MaybeXS->new(utf8 => 0, ascii => 1, allow_nonref => 1);

# Define the escape_javascript function
sub escape_javascript {
    my ($javascript) = @_;
    return '' unless defined $javascript;

    # Encode the string as a JSON string
    my $escaped = $json->encode($javascript);

    # Remove the surrounding quotes added by JSON encoding
    $escaped =~ s/^"(.*)"$/$1/;

    # Escape additional characters not handled by JSON encoding
    $escaped =~ s/`/\\`/g;   # Escape backticks
    $escaped =~ s/\$/\\\$/g; # Escape dollar signs
    $escaped =~ s/'/\\'/g;   # Escape single quotes
    $escaped =~ s{</}{<\\/}g; # Prevent closing an enclosing script element

    return $escaped;
}

sub generate_error_message {
  my ($msg, $template, $source) = @_;

  warn "RAW MESSAGE: [$msg]" if $ENV{DEBUG_TEMPLATE_EMBEDDED_PERL};

  return $msg if _has_render_stack($msg);

  $source = $source ? "$source" : 'unknown';

  my @files;
  push @files, [$1, $2, $3, $msg] while $msg =~ /^(.+?) at\s+(.+?)\s+line\s+(\d+)/gm;

  return $msg unless @files;

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

  return length($text) ? "$text\n" : $msg;
}

sub decorate_render_error {
  my ($error, $stack) = @_;

  return $error if _has_render_stack($error);
  return $error unless $stack && @$stack;

  my $separator = $error =~ /\n\z/ ? "\n" : "\n\n";
  my $render_stack = "Render stack:\n";
  for my $entry (@$stack) {
    my $kind = $entry->{kind};
    my $identifier = $entry->{identifier};
    my $source = defined($entry->{source}) && length($entry->{source})
      ? $entry->{source}
      : 'unknown';
    $render_stack .= "  $kind $identifier ($source)\n";
  }

  return $error . $separator . $render_stack;
}

sub _has_render_stack {
  my ($error) = @_;
  return defined($error)
    && $error =~ /(?:\A|\n)Render stack:\n(?:  [^\n]+(?:\n|\z))+\z/;
}

1;


=head1 NAME

Template::EmbeddedPerl::Utils - Utility functions for Template::EmbeddedPerl

=head1 DESCRIPTION

This module provides utility functions for L<Template::EmbeddedPerl>. It is not intended to be used directly.

=head1 EXPORTS

=head2 normalize_linefeeds

  my $normalized = normalize_linefeeds($template);

Normalize the line endings to \n from mac and windows format.

=head2 uri_escape

  my $escaped = uri_escape($string);

Escape the uri string.

=head2 escape_javascript

  my $escaped = escape_javascript($javascript);

Escape a value so that it can be embedded in a JavaScript string. This escapes quotes,
backticks, dollar signs, JSON control characters, and closing HTML tags. It is not a
general JavaScript sanitizer and does not make untrusted JavaScript code safe to execute.

=head2 generate_error_message

  my $error_message = generate_error_message($msg, $template, $source);

Generate an error message.

=head1 SEE ALSO
  
L<Template::EmbeddedPerl>

=head1 AUTHOR
  
See L<Template::EmbeddedPerl>
 
=head1 COPYRIGHT & LICENSE
  
See L<Template::EmbeddedPerl>
 
=cut
