package Template::EmbeddedPerl::RenderFrame;

use strict;
use warnings;

sub new { bless {render_stack => [], named_content => {}}, $_[0] }
sub render_stack { $_[0]->{render_stack} }
sub current_scope { $_[0]->{render_stack}->[-1] }

sub push_render {
    my ($self, %entry) = @_;
    $entry{layouts} = [];
    push @{$self->{render_stack}}, \%entry;
    return \%entry;
}

sub pop_render { pop @{$_[0]->{render_stack}} }

sub register_layout {
    my ($self, $identifier, @args) = @_;
    push @{$self->current_scope->{layouts}}, [$identifier, \@args];
    return;
}

sub take_layouts {
    my ($self) = @_;
    my @layouts = splice @{$self->current_scope->{layouts}};
    return \@layouts;
}

sub with_body {
    my ($self, $body, $callback) = @_;
    local $self->{default_body} = $body;
    return $callback->();
}

sub default_body {
    my ($self) = @_;
    return defined($self->{default_body}) ? $self->{default_body} : '';
}

sub append_content {
    my ($self, $name, $value) = @_;
    push @{$self->{named_content}{$name}}, $value;
    return;
}

sub replace_content {
    my ($self, $name, $value) = @_;
    $self->{named_content}{$name} = [$value];
    return;
}

sub content {
    my ($self, $name) = @_;
    return join '', @{$self->{named_content}{$name} || []};
}

sub has_content {
    my ($self, $name) = @_;
    return length $self->content($name) ? 1 : 0;
}

1;
