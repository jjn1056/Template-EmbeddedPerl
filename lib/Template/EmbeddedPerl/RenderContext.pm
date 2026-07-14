package Template::EmbeddedPerl::RenderContext;

use strict;
use warnings;

use Carp 'croak';
use Scalar::Util ();
use Template::EmbeddedPerl::Utils 'decorate_render_error';

our $SOURCE_OBSERVER;

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

    return $self->execute_render(
        {
            kind => $kind,
            identifier => $identifier,
        },
        sub {
            my ($entry) = @_;
            my $compiled = $self->_load_compiled_file($entry, $identifier);
            return $compiled->_execute_with_context(
                $self->with(source => $entry->{source}),
                @args,
            );
        },
    );
}

sub render_view_object {
    my ($self, $view) = @_;
    my $kind = @{$self->frame->render_stack} ? 'view' : 'root';
    return $self->execute_render(
        {
            kind => $kind,
            identifier => Scalar::Util::blessed($view),
        },
        sub {
            my ($entry) = @_;
            my $template_identifier = $self->engine->_template_for_view($view, $self);
            my $compiled = $self->_load_compiled_file($entry, $template_identifier);
            return $compiled->_execute_with_context(
                $self->with(view => $view, source => $entry->{source}),
            );
        },
    );
}

sub _load_compiled_file {
    my ($self, $entry, $identifier) = @_;
    local $SOURCE_OBSERVER = sub { $entry->{source} = $_[0] };
    my $compiled = $self->engine->from_file($identifier);
    $entry->{source} = $compiled->{source} if defined $compiled->{source};
    return $compiled;
}

sub execute_render {
    my ($self, $entry, $callback) = @_;
    my $frame = $self->frame;
    my $active_entry = $frame->push_render(
        %$entry,
        view => $self->view,
    );

    my ($ok, $output, $error);
    $ok = eval {
        $output = $callback->($active_entry);
        1;
    };
    $error = $@ unless $ok;

    my $stack = [map { +{%$_} } @{$frame->render_stack}];
    $frame->pop_render(failed => !$ok);
    die decorate_render_error($error, $stack) unless $ok;

    return $output;
}

sub build_child_view {
    my ($self, $target, $args) = @_;

    return $target if Scalar::Util::blessed($target) && !@$args;
    croak 'Preconstructed view objects do not accept constructor arguments'
        if Scalar::Util::blessed($target);

    croak 'Logical view target must be a blessed object or a non-empty logical name'
        unless defined($target) && !ref($target) && length($target);

    croak "Odd constructor argument list for logical view '$target'"
        if @$args % 2;

    my $resolver = $self->engine->{view_resolver};
    croak "Logical view '$target' requires a resolver with build_view"
        unless $resolver && $resolver->can('build_view');

    my %constructor_args = @$args;
    my $view = $resolver->build_view($target, \%constructor_args, $self);
    croak "Resolver did not return a blessed view for '$target'"
        unless Scalar::Util::blessed($view);

    return $view;
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
