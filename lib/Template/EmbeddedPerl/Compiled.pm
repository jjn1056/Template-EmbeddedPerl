package Template::EmbeddedPerl::Compiled;

use warnings;
use strict;

sub render {
  my ($self, @args) = @_;
  my $output;
  return eval { $output = $self->{code}->(@args); 1 } ? $output : $@;
}

1;
