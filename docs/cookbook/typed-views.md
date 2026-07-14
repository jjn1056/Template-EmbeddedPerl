# Template Composition and Typed Views

This cookbook uses Perl 5.40. `Moo` is used only to make the typed examples
concise and is a test dependency, not a runtime dependency of
Template::EmbeddedPerl. The engine accepts any blessed view object. Moo is not
required by the engine.

## Untyped Pages

Configure `smart_lines` to make full-line template directives ordinary Perl
without visible `<%` and `%>` delimiters. `directories` is an ordered search
path: the first directory containing an identifier wins for pages, partials,
layouts, and typed view templates.

```perl
use Template::EmbeddedPerl;

my $templates = Template::EmbeddedPerl->new(
    directories => ['/srv/app/templates', '/srv/shared/templates'],
    auto_escape => 1,
    smart_lines => 1,
);
```

With that configuration, `/srv/app/templates/pages/contacts.epl` overrides
`/srv/shared/templates/pages/contacts.epl`.

Template arguments are declared once, before executable template code. An
argument without a default is required, and a scalar expression is evaluated as
the default when its argument is absent. A coderef is a lazy default factory;
it runs only when its argument is absent. An explicit `undef` is a supplied
value.

`pages/contacts.epl`:

```epl
% args $name, $title = 'Contacts', $heading = sub { "Contacts for $name" }
% layout 'layouts/application', title => $title
<%= content_for 'css', sub { '<meta name="theme" content="first">' } %>
<%= content_replace 'css', sub { '<link href="/contacts.css">' } %>
<main>
  <h1><%= $heading %></h1>
  <ul><%= partial 'contacts/item', name => $name %></ul>
</main>
```

`contacts/item.epl` has its own named argument contract. A partial inherits
the caller's `$self`, if there is one, and is returned as safe rendered output,
so `auto_escape` does not escape it again.

```epl
% args $name
<li><%= $name %></li>
```

Layouts have an independent argument contract. `yield` returns the rendered
page body, while `yield 'css'` returns the named content accumulated by
`content_for`. `content_replace` replaces rather than appends a named block,
and `has_content 'css'` checks whether a named block has nonempty output.
Here, the replacement leaves only the stylesheet link for the layout to yield.

`layouts/application.epl`:

```epl
% args $title = 'Default title'
<!doctype html>
<title><%= $title %></title>
% if (has_content 'css') {
<head><%= yield 'css' %></head>
% } else {
<head><meta name="theme" content="default"></head>
% }
<body><%= yield %></body>
```

Render it with named arguments:

```perl
my $html = $templates->from_file('pages/contacts')->render(
    name => '<Ada>',
);
```

The `name` value is escaped in the partial exactly once. Passing
`heading => undef` suppresses the lazy default; passing a concrete `heading`
also bypasses it.

## Typed Views

Typed views give templates a lexical `$self`. Use `render_view($view)` for a
top-level typed object. Calling the legacy `render` methods with a blessed
argument remains supported, but that object stays in `@_`; it is not inferred
as `$self`.

These complete Moo classes are illustrative. An application may use any other
object system that returns blessed objects from its constructors.

### Default Logical Children

Without a factory, a logical child is constructed with only the values supplied
by its `view` call. Its constructor must therefore require only those template
arguments.

```perl
package MyApp::View::HTML::SimplePage;
use v5.40;
use Moo;

has title => (is => 'ro', required => 1);

package MyApp::View::HTML::SimpleItem;
use v5.40;
use Moo;

has label => (is => 'ro', required => 1);

sub template { 'components/simple_item' }
```

This complete flow has no `view_factory` configuration. The logical item
receives its required `label` directly from the template.

```perl
my $simple_engine = Template::EmbeddedPerl->new(
    directories => ['/srv/app/templates', '/srv/shared/templates'],
    auto_escape => 1,
    smart_lines => 1,
    preamble => 'use v5.40;',
    view_namespace => 'MyApp::View',
);

my $html = $simple_engine->render_view(
    MyApp::View::HTML::SimplePage->new(title => 'Contacts'),
);
```

`html/simple_page.epl`:

```epl
<section><%= view 'HTML::SimpleItem', label => $self->title %></section>
```

`components/simple_item.epl`:

```epl
<span><%= $self->label %></span>
```

### Factory-Backed Wrapper Tree

When logical children require injected `root` and `parent` values, configure a
factory in the engine before calling `render_view`.

```perl
package MyApp::View::HTML::ContactList;
use v5.40;
use Moo;

has title => (is => 'ro', required => 1);
has contacts => (is => 'ro', required => 1);
has navbar => (is => 'lazy', builder => '_build_navbar');

sub _build_navbar ($self) {
    return MyApp::View::HTML::Navbar->new(
        active => 'contacts',
        root => $self,
        parent => $self,
    );
}

package MyApp::View::HTML::Page;
use v5.40;
use Moo;

has title => (is => 'ro', required => 1);
has root => (is => 'ro', required => 1);
has parent => (is => 'ro', required => 1);

package MyApp::View::HTML::Navbar;
use v5.40;
use Moo;

has active => (is => 'ro', required => 1);
has root => (is => 'ro', required => 1);
has parent => (is => 'ro', required => 1);

sub template { 'components/navbar' }

package MyApp::View::HTML::Item;
use v5.40;
use Moo;

has contact => (is => 'ro', required => 1);
has root => (is => 'ro', required => 1);
has parent => (is => 'ro', required => 1);
```

The root view is convention-resolved. With `view_namespace => 'MyApp::View'`,
the package mapping is:

```text
MyApp::View::HTML::ContactList -> html/contact_list.epl
```

Each package segment is converted independently: `HTML` becomes `html`,
`HTMLPage` becomes `html_page`, and `ContactList` becomes `contact_list`.

For a logical call such as `view 'HTML::Navbar', active => 'contacts'`, the
engine prefixes `view_namespace` and loads `MyApp::View::HTML::Navbar`. Moo
remains optional; the engine only relies on an ordinary constructor returning a
blessed object.

Create the factory-backed engine and root in application code. The root's lazy
`navbar` is a preconstructed child. The item and wrapper are logical children,
so the factory adds their `root` and `parent` constructor arguments.

```perl
my $engine = Template::EmbeddedPerl->new(
    directories => ['/srv/app/templates', '/srv/shared/templates'],
    auto_escape => 1,
    smart_lines => 1,
    preamble => 'use v5.40;',
    view_namespace => 'MyApp::View',
    view_factory => sub {
        my ($class, $args, $context) = @_;
        return $class->new(
            %$args,
            root => $context->root_view,
            parent => $context->view,
        );
    },
);

my $root = MyApp::View::HTML::ContactList->new(
    title => 'Contacts',
    contacts => [{name => 'Ada'}],
);
my $html = $engine->render_view($root);
```

`html/contact_list.epl` renders the preconstructed navbar, a logical item, and
a logical wrapper. Within the wrapper callback, lexical `$self` remains the
caller (the contact list), while `$page` is the newly built wrapper.

```epl
%= view $self->navbar
%= view 'HTML::Page', title => $self->title, sub ($page) {
  <h1><%= $self->title %> / <%= $page->title %></h1>
  % for my $contact ($self->contacts->@*) {
  %= view 'HTML::Item', contact => $contact
  % }
% }
```

The wrapper template has a different `$self`: the page wrapper itself. A
logical child rendered there receives the page as `parent`, while every nested
child receives the original contact list as `root`.

`html/page.epl`:

```epl
<section class="page">
  <header><%= $self->title %></header>
  <%= yield %>
  <%= view 'HTML::Item', contact => {name => 'Footer'} %>
</section>
```

The navbar and item use explicit template methods, while the contact list and
page use the same ordered directories through convention lookup:

`components/navbar.epl`:

```epl
<nav data-active="<%= $self->active %>"><%= $self->root->title %> / <%= $self->parent->title %></nav>
```

`components/contact_item.epl`:

```epl
<li><%= $self->contact->{name} %> (root: <%= $self->root->title %>; parent: <%= $self->parent->title %>)</li>
```

Use a `template` method for every explicit template override:

```perl
package MyApp::View::HTML::Item;

sub template { 'components/contact_item' }
```

The engine resolves a nonempty view `template` method first, then the
`view_namespace` convention. In this example the navbar and item use explicit
templates, and contact list/page use convention lookup. All paths use the same
ordered `directories` search path.

The configured factory receives `$args`, which contains only values supplied by
the template,
`$context->view` is the current parent, and `$context->root_view` is the
original typed root. Preconstructed objects bypass this callback.

## Failures and Reuse

Each top-level `render`, compiled-template `render`, or `render_view` call
creates exactly one render frame. Partials, layouts, and nested views share it.
Cycles are rejected with the active render chain. A nested failure is decorated
with one source-aware `Render stack`, then frame state is cleaned up so the same
engine can render another top-level request without leaked body, named content,
layouts, or stack entries.
