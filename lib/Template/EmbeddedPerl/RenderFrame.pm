package Template::EmbeddedPerl::RenderFrame;

use strict;
use warnings;

sub new { bless {render_stack => []}, $_[0] }
sub render_stack { $_[0]->{render_stack} }
sub current_scope { $_[0]->{render_stack}->[-1] }

sub push_render {
    my ($self, %entry) = @_;
    $entry{layouts} = [];
    push @{$self->{render_stack}}, \%entry;
    return \%entry;
}

sub pop_render { pop @{$_[0]->{render_stack}} }

1;
