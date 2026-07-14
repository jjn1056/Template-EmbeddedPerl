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

my $template_directory = File::Spec->catdir(qw(t templates views));
my $engine = Template::EmbeddedPerl->new(
    directories => [$template_directory],
    view_namespace => 'Local::View',
    auto_escape => 1,
);

throws_ok {
    Local::View::HTML::Contacts::Index->new(contacts => []);
} qr/Missing required arguments?: title/,
    'Moo rejects a missing required attribute before rendering';

my $page = Local::View::HTML::Contacts::Index->new(
    title => 'Contacts',
    contacts => [
        {name => 'Jane'},
        {name => 'John'},
    ],
);

is(
    $engine->render_view($page),
    "<h1>Contacts</h1>\n<p>Jane, John</p>\n<p>args: 0</p>\ncaptured\n",
    'render_view resolves a Moo root by package convention and exposes lexical self',
);
is($Local::View::captured_context->view, $page, 'root context view is the rendered object');
is($Local::View::captured_context->root_view, $page, 'root context root_view is the rendered object');
is(
    $Local::View::captured_context->frame->current_scope,
    undef,
    'typed root render scope is cleaned up after rendering',
);

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
