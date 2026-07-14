use strict;
use warnings;

use File::Path 'make_path';
use File::Spec;
use File::Temp 'tempdir';
use Moo;
use Test::Most;
use Template::EmbeddedPerl;

my $cookbook = File::Spec->catfile(qw(docs cookbook typed-views.md));
ok(-e $cookbook, 'the typed-view cookbook is present');

sub write_template {
    my ($directory, $identifier, $content) = @_;
    my @parts = split m{/}, $identifier;
    my $file = pop @parts;
    my $path = File::Spec->catfile($directory, @parts, "$file.epl");
    my ($volume, $directories) = File::Spec->splitpath($path);
    make_path($directories);
    open my $fh, '>', $path or die "Cannot write $path: $!";
    print {$fh} $content;
    close $fh or die "Cannot close $path: $!";
}

{
    package Documentation::View::HTMLPage::ContactList;
    use Moo;

    has title => (is => 'ro', required => 1);
    has prebuilt_item => (is => 'ro', required => 1);
}

{
    package Documentation::View::HTMLPage::Shell;
    use Moo;

    has title => (is => 'ro', required => 1);
    has root => (is => 'ro', required => 1);
    has parent => (is => 'ro', required => 1);
}

{
    package Documentation::View::HTML::Navbar;
    use Moo;

    has active => (is => 'ro', required => 1);
    has root => (is => 'ro', required => 1);
    has parent => (is => 'ro', required => 1);

    sub template { 'components/navbar' }
}

{
    package Documentation::View::HTML::ContactItem;
    use Moo;

    has label => (is => 'ro', required => 1);
    has root => (is => 'ro');
    has parent => (is => 'ro');

    sub template { 'components/contact_item' }
}

{
    package Documentation::View::HTML::HelperMatrix;
    use Moo;

    has title => (is => 'ro', required => 1);
}

{
    package Documentation::View::HTML::HelperWrapper;
    use Moo;

    has title => (is => 'ro', required => 1);
    has root => (is => 'ro', required => 1);
    has parent => (is => 'ro', required => 1);
}

my $temporary = tempdir(CLEANUP => 1);
my $first = File::Spec->catdir($temporary, 'first');
my $second = File::Spec->catdir($temporary, 'second');

write_template($first, 'pages/index', <<'EPL');
% args $name, $title = 'Directory One', $subtitle = sub {
%   record_default($name);
%   return "Welcome, $name";
% }
% layout 'layouts/application', title => $title
<%= content_for 'css', sub { '<meta name="theme" content="first">' } %>
<%= content_replace 'css', sub { '<link href="/contacts.css">' } %>
<main><h1><%= $subtitle %></h1><ul><%= partial 'contacts/item', name => $name %></ul></main>
EPL

write_template($first, 'layouts/application', <<'EPL');
% args $title = 'Default'
<!doctype html><title><%= $title %></title><head>
% if (has_content 'css') {
<%= yield 'css' %>
% } else {
<meta name="theme" content="default">
% }
</head><body><%= yield %></body>
EPL

write_template($first, 'contacts/item', <<'EPL');
% args $name
<li><%= $name %></li>
EPL

write_template($second, 'pages/index', '<p>second directory</p>');

write_template($first, 'html_page/contact_list', <<'EPL');
<section class="contacts" data-source="convention"><%= view 'HTML::Navbar', active => 'contacts' %><%= view $self->prebuilt_item %><%= view 'HTML::ContactItem', label => '<Logical>' %><%= view 'HTMLPage::Shell', title => "Shell " . $self->title, sub { %><p>body-self=<%= $self->title %>; callback=<%= $_[0]->title %></p><% } %></section>
EPL

write_template($first, 'html_page/shell', <<'EPL');
<article data-source="convention" data-wrapper="<%= $self->title %>"><h1><%= $self->title %></h1><%= yield %><%= view 'HTML::Navbar', active => 'wrapper' %></article>
EPL

write_template($first, 'components/navbar', <<'EPL');
<nav data-source="object"><%= $self->active %> root=<%= $self->root->title %> parent=<%= $self->parent->title %></nav>
EPL

write_template($first, 'components/contact_item', <<'EPL');
<li class="contact" data-source="object"><%= typed_label $self->label %> root=<%= $self->root ? $self->root->title : 'none' %> parent=<%= $self->parent ? $self->parent->title : 'none' %></li>
EPL

write_template(
    $first,
    'html/helper_matrix',
    q{<% layout 'typed/helper_layout' %><root><%= typed_label 'root:' . $self->title %>|<%= partial 'typed/helper_partial' %>|<%= view 'HTML::HelperWrapper', title => 'wrapped', sub { %><%= typed_label 'body:' . $self->title %><% } %></root>},
);
write_template(
    $first,
    'html/helper_wrapper',
    q{<wrapper><%= typed_label 'wrapper:' . $self->title %>|<%= yield %></wrapper>},
);
write_template(
    $first,
    'typed/helper_partial',
    q{<partial><%= typed_label 'partial:' . $self->title %></partial>},
);
write_template(
    $first,
    'typed/helper_layout',
    q{<layout><%= typed_label 'layout:' . $self->title %>|<%= yield %></layout>},
);

my $lazy_default_calls = 0;
my $untyped_engine = Template::EmbeddedPerl->new(
    directories => [$first, $second],
    auto_escape => 1,
    smart_lines => 1,
    helpers => {
        record_default => sub { $lazy_default_calls++ },
    },
);

is(
    $untyped_engine->from_file('pages/index')->render(name => '<Ada>'),
    "<!doctype html><title>Directory One</title><head>\n<link href=\"/contacts.css\">\n</head><body>\n\n"
        . "<main><h1>Welcome, &lt;Ada&gt;</h1><ul><li>&lt;Ada&gt;</li>\n</ul></main>\n</body>\n",
    'untyped page uses the first directory, content replacement, has_content, layout, and a once-escaped partial',
);
is($lazy_default_calls, 1, 'an absent lazy argument is evaluated once');
$untyped_engine->from_file('pages/index')->render(
    name => 'Ada',
    title => 'Provided',
    subtitle => undef,
);
is($lazy_default_calls, 1, 'an explicit undef does not evaluate a lazy argument default');

my @factory_calls;
my $typed_engine = Template::EmbeddedPerl->new(
    directories => [$first, $second],
    auto_escape => 1,
    smart_lines => 1,
    view_namespace => 'Documentation::View',
    helpers => {
        typed_label => sub {
            my ($engine, $label) = @_;
            return uc $label;
        },
    },
    view_factory => sub {
        my ($class, $args, $context) = @_;
        my $view = $class->new(
            %$args,
            root => $context->root_view,
            parent => $context->view,
        );
        push @factory_calls, {
            class => $class,
            args => {%$args},
            context => $context,
            view => $view,
        };
        return $view;
    },
);

is(
    $typed_engine->render_view(
        Documentation::View::HTML::HelperMatrix->new(title => 'Root'),
    ),
    '<layout>LAYOUT:ROOT|<root>ROOT:ROOT|<partial>PARTIAL:ROOT</partial>|'
        . '<wrapper>WRAPPER:WRAPPED|BODY:ROOT</wrapper></root></layout>',
    'helpers work with typed self in roots, partials, layouts, wrapper bodies, and wrapper templates',
);

my $root = Documentation::View::HTMLPage::ContactList->new(
    title => 'Contacts',
    prebuilt_item => Documentation::View::HTML::ContactItem->new(
        label => '<Prebuilt>',
    ),
);

is(
    $typed_engine->render_view($root),
    "<section class=\"contacts\" data-source=\"convention\"><nav data-source=\"object\">contacts root=Contacts parent=Contacts</nav>\n"
        . "<li class=\"contact\" data-source=\"object\">&lt;PREBUILT&gt; root=none parent=none</li>\n"
        . "<li class=\"contact\" data-source=\"object\">&lt;LOGICAL&gt; root=Contacts parent=Contacts</li>\n"
        . "<article data-source=\"convention\" data-wrapper=\"Shell Contacts\"><h1>Shell Contacts</h1><p>body-self=Contacts; callback=Shell Contacts</p>"
        . "<nav data-source=\"object\">wrapper root=Contacts parent=Shell Contacts</nav>\n</article>\n</section>\n",
    'render_view and nested view apply object template and convention precedence',
);

my ($root_navbar) = grep {
    $_->{class} eq 'Documentation::View::HTML::Navbar'
        && $_->{view}->active eq 'contacts'
} @factory_calls;
my ($wrapper) = grep {
    $_->{class} eq 'Documentation::View::HTMLPage::Shell'
} @factory_calls;
my ($wrapper_navbar) = grep {
    $_->{class} eq 'Documentation::View::HTML::Navbar'
        && $_->{view}->active eq 'wrapper'
} @factory_calls;

is($root_navbar->{view}->root, $root, 'logical root child receives the typed root identity');
is($root_navbar->{view}->parent, $root, 'logical root child receives the caller as parent');
is($wrapper->{view}->root, $root, 'logical wrapper receives the typed root identity');
is($wrapper->{view}->parent, $root, 'logical wrapper receives the body caller as parent');
is($wrapper_navbar->{context}->view, $wrapper->{view}, 'wrapper template scopes nested view construction to the wrapper');
is($wrapper_navbar->{view}->parent, $wrapper->{view}, 'wrapper template child receives the wrapper as parent');
ok(
    !(grep { $_->{view} == $root->prebuilt_item } @factory_calls),
    'preconstructed child bypasses the view factory',
);

done_testing;
