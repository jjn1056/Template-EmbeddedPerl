package Template::EmbeddedPerl::Compiled;

use warnings;
use strict;
use Template::EmbeddedPerl::Utils 'generate_error_message';

sub render {
  my ($self, @args) = @_;
  my $output;
  eval { $output = $self->{code}->(@args); 1 } or do {
    die generate_error_message($@, $self->{template});
  };
  return $output;
}

1;
