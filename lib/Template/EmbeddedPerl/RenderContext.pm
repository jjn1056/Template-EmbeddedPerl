package Template::EmbeddedPerl::RenderContext;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub engine    { $_[0]->{engine} }
sub frame     { $_[0]->{frame} }
sub view      { $_[0]->{view} }
sub root_view { $_[0]->{root_view} }
sub source    { $_[0]->{source} }

sub with {
    my ($self, %overrides) = @_;
    return ref($self)->new(%$self, %overrides);
}

1;
