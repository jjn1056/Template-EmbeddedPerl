# Template Composition and Typed Views

This cookbook uses Perl 5.40. `Moo` is used only to make the typed examples
concise and is a test dependency, not a runtime dependency of
Template::EmbeddedPerl. The engine accepts any blessed view object. It never
constructs or introspects Moo objects.

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
argument without a default is required, a scalar expression provides an eager
default, and a coderef is a lazy default. The lazy coderef runs only when its
argument is absent; an explicit `undef` is a supplied value.

`pages/contacts.epl`:

```epl
% args $name, $title = 'Contacts', $heading = sub { "Contacts for $name" }
% layout 'layouts/application', title => $title
<%= content_for 'css', sub { '<link href="/contacts.css">' } %>
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

`layouts/application.epl`:

```epl
% args $title = 'Default title'
<!doctype html>
<title><%= $title %></title>
% if (has_content 'css') {
<head><%= yield 'css' %></head>
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
object system, provided it constructs blessed objects itself.

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

An application resolver owns logical-name expansion, class loading,
construction, and its `root`/`parent` relationships. `build_view` receives the
logical name, constructor arguments, and active render context. This resolver
lets `template_for` choose a special item template while returning `undef` for
all other views, which leaves convention lookup available.

```perl
package MyApp::View::Resolver;
use v5.40;
use Moo;

sub build_view ($self, $logical_name, $args, $context) {
    my $class = "MyApp::View::$logical_name";
    eval "require $class; 1" or die $@;
    return $class->new(
        %$args,
        root => $context->root_view,
        parent => $context->view,
    );
}

sub template_for ($self, $view, $context) {
    return 'components/contact_item' if $view->isa('MyApp::View::HTML::Item');
    return;
}
```

Create the engine and root in application code. The root's lazy `navbar` is a
preconstructed child: the core does not invoke `build_view` for it. The item is
a logical child, so the resolver constructs it with the root and current parent.

```perl
my $resolver = MyApp::View::Resolver->new;
my $engine = Template::EmbeddedPerl->new(
    directories => ['/srv/app/templates', '/srv/shared/templates'],
    auto_escape => 1,
    smart_lines => 1,
    preamble => 'use v5.40;',
    view_namespace => 'MyApp::View',
    view_resolver => $resolver,
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

The explicit navbar and resolver-selected item are ordinary templates in the
same directories:

`components/navbar.epl`:

```epl
<nav data-active="<%= $self->active %>"><%= $self->root->title %> / <%= $self->parent->title %></nav>
```

`components/contact_item.epl`:

```epl
<li><%= $self->contact->{name} %> (root: <%= $self->root->title %>; parent: <%= $self->parent->title %>)</li>
```

The engine resolves a nonempty view `template` method first, then a nonempty
resolver `template_for` result, then the `view_namespace` convention. In this
example the navbar's explicit `components/navbar` wins, items use the resolver
result, and contact list/page use convention lookup. All paths use the same
ordered `directories` search path.

## Failures and Reuse

Each top-level `render`, compiled-template `render`, or `render_view` call
creates exactly one render frame. Partials, layouts, and nested views share it.
Cycles are rejected with the active render chain. A nested failure is decorated
with one source-aware `Render stack`, then frame state is cleaned up so the same
engine can render another top-level request without leaked body, named content,
layouts, or stack entries.
