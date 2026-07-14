use Test::Most;
use File::Spec;
use Template::EmbeddedPerl;

{
    package Local::View::HTML::Contacts::Index;
    use Moo;

    has title => (is => 'ro', required => 1);
    has contacts => (is => 'ro', required => 1);

    sub capture_context {
        my ($self) = @_;
        $Local::View::captured_context =
            Template::EmbeddedPerl->_current_render_context('capture_context');
        return 'captured';
    }
}

{
    package Local::View::Explicit;
    use Moo;

    has title => (is => 'ro', required => 1);

    sub template { 'components/navigation' }
}

{
    package Local::View::HTML::Page;
    use Moo;

    has title => (is => 'ro', required => 1);
    has root => (is => 'ro', required => 1);
    has parent => (is => 'ro', required => 1);
}

{
    package Local::View::HTML::Navbar;
    use Moo;

    has root => (is => 'ro', required => 1);
    has parent => (is => 'ro', required => 1);
}

{
    package Local::View::HTML::Contacts::Item;
    use Moo;

    has contact => (is => 'ro', required => 1);
    has root => (is => 'ro', required => 1);
    has parent => (is => 'ro', required => 1);
}

{
    package Local::View::MissingWrapper;
    use Moo;

    has root => (is => 'ro', required => 1);
    has parent => (is => 'ro', required => 1);

    sub template { 'missing/wrapper' }
}

{
    package Local::View::Resolver;
    use Moo;

    has build_calls => (is => 'ro', default => sub { [] });

    sub build_view {
        my ($self, $name, $args, $context) = @_;
        my $class = "Local::View::$name";
        my $view = $class->new(
            %$args,
            root => $context->root_view,
            parent => $context->view,
        );
        push @{$self->build_calls}, {
            name => $name,
            args => {%$args},
            context => $context,
            view => $view,
        };
        return $view;
    }

    sub template_for { return }
}

my $template_directory = File::Spec->catdir(qw(t templates views));
my $resolver = Local::View::Resolver->new;
my $engine = Template::EmbeddedPerl->new(
    directories => [$template_directory],
    view_namespace => 'Local::View',
    view_resolver => $resolver,
    auto_escape => 1,
    preamble => 'use v5.40;',
);

throws_ok {
    Local::View::HTML::Contacts::Index->new(contacts => []);
} qr/Missing required arguments?: title/,
    'Moo rejects a missing required attribute before rendering';

my $root = Local::View::HTML::Contacts::Index->new(
    title => 'Contacts',
    contacts => [
        {name => 'Jane'},
        {name => 'John'},
    ],
);

is(
    $engine->render_view($root),
    "<section class=\"page\">\n"
        . "<header>Contacts</header>\n"
        . "<p>page-root=Contacts; page-parent=Contacts</p>\n"
        . "<nav>root=Contacts; parent=Contacts</nav>\n"
        . "\n"
        . "<main>\n"
        . "\n"
        . "  <h1>Contacts</h1>\n"
        . "  <p>root=Contacts</p>\n"
        . "<article>Jane; root=Contacts; parent=Contacts</article>\n"
        . "\n\n"
        . "</main>\n"
        . "</section>\n"
        . "\n"
        . "captured\n",
    'render_view composes a logical typed wrapper and leaf around a Moo root',
);
is($Local::View::captured_context->view, $root, 'root context view is the rendered object');
is($Local::View::captured_context->root_view, $root, 'root context root_view is the rendered object');
is(
    $Local::View::captured_context->frame->current_scope,
    undef,
    'typed root render scope is cleaned up after rendering',
);

my ($page_call) = grep { $_->{name} eq 'HTML::Page' } @{$resolver->build_calls};
my ($item_call) = grep { $_->{name} eq 'HTML::Contacts::Item' } @{$resolver->build_calls};
my ($navbar_call) = grep { $_->{name} eq 'HTML::Navbar' } @{$resolver->build_calls};

isa_ok($page_call->{view}, 'Local::View::HTML::Page', 'wrapper callback receives the constructed page');
is($page_call->{context}->view, $root, 'page resolver context exposes the caller view');
is($page_call->{context}->root_view, $root, 'page resolver context preserves the top-level root');
is($page_call->{view}->root, $root, 'page receives the top-level root');
is($page_call->{view}->parent, $root, 'page receives the caller as parent');
is($item_call->{context}->view, $root, 'leaf rendered in wrapper body keeps the caller context');
is($item_call->{view}->root, $root, 'leaf receives the top-level root');
is($item_call->{view}->parent, $root, 'leaf receives the body caller as parent');
is($navbar_call->{context}->view, $page_call->{view}, 'wrapper template child sees the wrapper as caller');
is($navbar_call->{view}->root, $root, 'wrapper child receives the top-level root');
is($navbar_call->{view}->parent, $page_call->{view}, 'wrapper child receives the wrapper as parent');

my $preconstructed_item = Local::View::HTML::Contacts::Item->new(
    contact => {name => 'Prebuilt'},
    root => $root,
    parent => $root,
);
my $object_leaf = $engine->from_string(
    '%= view $_[0]',
    source => 'object-leaf.epl',
);
my $object_context = $engine->_new_render_context(
    view => $root,
    root_view => $root,
    source => 'object-leaf.epl',
);
my $build_count = @{$resolver->build_calls};
is(
    $object_leaf->_render_with_context(
        $object_context,
        {kind => 'root', identifier => 'object-leaf', source => 'object-leaf.epl'},
        $preconstructed_item,
    ),
    "<article>Prebuilt; root=Contacts; parent=Contacts</article>\n",
    'a preconstructed leaf view renders through the object path',
);
is(@{$resolver->build_calls}, $build_count, 'a preconstructed view bypasses build_view');

my $preconstructed_page = Local::View::HTML::Page->new(
    title => 'Object Page',
    root => $root,
    parent => $root,
);
my $object_wrapper = $engine->from_string(<<'EPL', source => 'object-wrapper.epl');
%= view $_[0], sub ($wrapper) {
  <strong><%= $wrapper->title %>|<%= $self->title %></strong>
% }
EPL
my $page_build_count = grep { $_->{name} eq 'HTML::Page' } @{$resolver->build_calls};
like(
    $object_wrapper->_render_with_context(
        $engine->_new_render_context(view => $root, root_view => $root),
        {kind => 'root', identifier => 'object-wrapper', source => 'object-wrapper.epl'},
        $preconstructed_page,
    ),
    qr{<header>Object Page</header>.*<strong>Object Page\|Contacts</strong>}s,
    'an object wrapper callback receives the child while lexical self remains the caller',
);
is(
    scalar(grep { $_->{name} eq 'HTML::Page' } @{$resolver->build_calls}),
    $page_build_count,
    'a preconstructed wrapper bypasses build_view',
);

my $object_with_args = $engine->from_string(
    q{<%= view $_[0], title => 'Not allowed' %>},
    source => 'object-with-args.epl',
);
throws_ok {
    $object_with_args->render($preconstructed_item);
} qr/Preconstructed view objects do not accept constructor arguments/,
    'a preconstructed view rejects constructor arguments clearly';

my $logical_with_odd_args = $engine->from_string(
    q{<%= view 'HTML::Page', title => 'Odd', 'dangling' %>},
    source => 'logical-with-odd-args.epl',
);
$build_count = @{$resolver->build_calls};
throws_ok {
    $logical_with_odd_args->_render_with_context(
        $engine->_new_render_context(view => $root, root_view => $root),
        {kind => 'root', identifier => 'logical-with-odd-args', source => 'logical-with-odd-args.epl'},
    );
} qr/Odd constructor argument list for logical view 'HTML::Page'/,
    'a logical view rejects an odd constructor list';
is(@{$resolver->build_calls}, $build_count, 'odd logical arguments fail before build_view');

my $without_resolver = Template::EmbeddedPerl->new(
    directories => [$template_directory],
    view_namespace => 'Local::View',
);
my $logical_without_resolver = $without_resolver->from_string(
    q{<%= view 'HTML::Navbar' %>},
    source => 'logical-without-resolver.epl',
);
throws_ok {
    $logical_without_resolver->_render_with_context(
        $without_resolver->_new_render_context(view => $root, root_view => $root),
        {kind => 'root', identifier => 'logical-without-resolver', source => 'logical-without-resolver.epl'},
    );
} qr/Logical view 'HTML::Navbar' requires a resolver with build_view/,
    'a logical child requires resolver construction support';

my $nested_wrappers = $engine->from_string(<<'EPL', source => 'nested-wrappers.epl');
%= view 'HTML::Page', title => 'One', sub ($one) {
%= view 'HTML::Page', title => 'Two', sub ($two) {
%= view 'HTML::Page', title => 'Three', sub ($three) {
%= view 'HTML::Contacts::Item', contact => $self->contacts->[1]
% }
% }
% }
EPL
my $nested_output = $nested_wrappers->_render_with_context(
    $engine->_new_render_context(view => $root, root_view => $root),
    {kind => 'root', identifier => 'nested-wrappers', source => 'nested-wrappers.epl'},
);
like(
    $nested_output,
    qr{<header>One</header>.*<header>Two</header>.*<header>Three</header>.*<article>John;}s,
    'three typed wrappers nest in order and yield an inner leaf view',
);
is(
    scalar(() = $nested_output =~ /<section class="page">/g),
    3,
    'each nested typed wrapper renders exactly once',
);

my $missing_wrapper = Local::View::MissingWrapper->new(root => $root, parent => $root);
my $failing_wrapper = $engine->from_string(<<'EPL', source => 'failing-wrapper.epl');
%= view $_[0], sub ($wrapper) {
body that must be restored
% }
EPL
my $failure_context = $engine->_new_render_context(view => $root, root_view => $root);
throws_ok {
    $failing_wrapper->_render_with_context(
        $failure_context,
        {kind => 'root', identifier => 'failing-wrapper', source => 'failing-wrapper.epl'},
        $missing_wrapper,
    );
} qr/Template 'missing\/wrapper' not found/,
    'a wrapper template failure propagates';
is($failure_context->frame->default_body, '', 'a wrapper failure restores the previous body');

my $explicit = Local::View::Explicit->new(title => 'Navigation');
is(
    $engine->render_view($explicit),
    "<nav>Navigation</nav>\n",
    'an explicit template method bypasses convention lookup',
);

for my $invalid (undef, {}, 'Local::View::Explicit') {
    throws_ok {
        $engine->render_view($invalid);
    } qr/render_view requires a blessed view object/,
        'render_view rejects an unblessed value';
}

my $legacy = $engine->from_string(
    q{<%= defined($self) ? ref($self) : 'no self' %>|<%= ref($_[0]) %>|<%= $_[0]->title %>},
    source => 'legacy-object.epl',
);
is(
    $legacy->render($explicit),
    'no self|Local::View::Explicit|Navigation',
    'legacy rendering keeps a blessed object in positional arguments without inferring self',
);

done_testing;
