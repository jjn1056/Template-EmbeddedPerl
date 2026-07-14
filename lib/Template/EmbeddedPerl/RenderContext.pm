package Template::EmbeddedPerl::RenderContext;

use strict;
use warnings;

use Carp 'croak';

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

sub render_file {
    my ($self, $kind, $identifier, @args) = @_;
    croak "Invalid $kind identifier"
        unless defined($identifier) && !ref($identifier);

    my $compiled = $self->engine->from_file($identifier);
    return $compiled->_render_with_context(
        $self->with(source => $compiled->{source}),
        {
            kind => $kind,
            identifier => $identifier,
            source => $compiled->{source},
        },
        @args,
    );
}

sub render_view_object {
    my ($self, $view) = @_;
    my $identifier = $self->engine->_template_for_view($view, $self);
    my $kind = @{$self->frame->render_stack} ? 'view' : 'root';
    return $self->with(view => $view)->render_file($kind, $identifier);
}

sub named_arguments {
    my ($self, $args) = @_;
    croak 'Odd template argument list' if @$args % 2;

    my @copy = @$args;
    my %named;
    while (@copy) {
        my ($name, $value) = splice @copy, 0, 2;
        croak "Duplicate template argument '$name'" if exists $named{$name};
        $named{$name} = $value;
    }
    return \%named;
}

sub take_required_argument {
    my ($self, $named, $name) = @_;
    croak "Missing required template argument '$name'" unless exists $named->{$name};
    return delete $named->{$name};
}

sub take_optional_argument {
    my ($self, $named, $name, $factory) = @_;
    return delete $named->{$name} if exists $named->{$name};
    return $factory->();
}

sub assert_no_arguments {
    my ($self, $named) = @_;
    my @unknown = sort keys %$named;
    croak "Unknown template argument '$unknown[0]'" if @unknown;
    return;
}

1;
