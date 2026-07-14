# Typed View Composition Design

**Date:** 2026-07-13
**Revised:** 2026-07-14
**Status:** Approved design

## Summary

Template::EmbeddedPerl will add a low-ceremony composition layer with three
distinct operations:

- `partial` renders a simple untyped fragment.
- `layout` wraps output in a simple untyped template.
- `view` renders a typed view object as either a leaf or a wrapper. The object
  may be supplied by the caller or constructed from a logical name.

Typed root views and nested typed views use the same rendering and template
resolution path. The engine remains independent of Moo, but provides a
convention-based constructor for logical view names: it expands the configured
namespace, loads the class, and calls `new` with the explicit template arguments.
Applications that need dependency injection can replace only that construction
step with a `view_factory` callback.

Rails-style default and named content blocks make layouts and wrappers useful
without requiring callers to manually pass rendered strings. Smart line
directives remove whitespace-control ceremony while existing rendering APIs and
template argument behavior remain compatible.

## Goals

1. Reduce boilerplate for partials, layouts, and reusable view components.
2. Make strongly typed Moo view objects natural to use from templates.
3. Let typed views act as pages, leaf components, or arbitrarily nested
   wrappers.
4. Give root and nested typed views identical template resolution semantics.
5. Support default and named content blocks shared across nested rendering.
6. Preserve existing `render(@args)`, `@_`, `shift`, helper, escaping, and block
   capture behavior.
7. Keep Moo and framework-specific object construction outside the core
   distribution's runtime dependencies.

## Non-goals

- Template::EmbeddedPerl will not become a dependency injection container.
- The core will not inspect Moo metadata or turn template arguments into Moo
  attributes.
- The core will not define a general-purpose view resolver protocol.
- The core will not infer that an arbitrary blessed argument passed to the
  existing `render` method is a view.
- Typed and untyped rendering will not use separate template languages.
- This design does not require view classes to depend on or invoke
  Template::EmbeddedPerl directly.

## Vocabulary

| Operation | New view object | Template `$self` | Intended use |
| --- | --- | --- | --- |
| `partial` | No | Inherits caller | Simple reusable fragment |
| `layout` | No | Inherits caller | Simple outer template with yields |
| `view` | Yes, or accepts an existing one | The child view | Typed component, page, or wrapper |

These names represent separate contracts rather than aliases. A caller chooses
`partial` or `layout` when an additional typed object would add ceremony, and
`view` when the rendered unit has a typed state or behavior contract.

## Architecture

### Engine

The Template::EmbeddedPerl engine continues to own configuration, compilation,
template directories, caching, helper registration, and escaping. Existing
`render`, `from_string`, `from_file`, and compiled-template APIs remain valid.

The engine gains an explicit typed entry point:

```perl
my $output = $engine->render_view($view);
```

`render_view` is deliberately distinct from `render`. It never guesses whether
an argument is a view and therefore cannot reinterpret existing calls that pass
arbitrary objects through `@_`.

### Render context

Every render executes with an internal context containing:

- the engine;
- the active render frame;
- the current typed view, if any;
- the current template source;
- the active template and view stacks used for diagnostics and cycle detection.

Generated template code receives the context separately from legacy arguments.
Conceptually, a compiled template behaves as follows:

```perl
sub {
    my ($context, @args) = @_;
    local @_ = @args;
    my $self = $context->view;

    # compiled template body
}
```

The implementation can use a more efficient internal calling convention, but
it must preserve the observable behavior: legacy arguments remain in `@_`, and
typed templates receive the active view as lexical `$self`.

### Render frame

A render frame owns request-local composition state:

- captured body content;
- named content blocks;
- pending layouts;
- root and parent rendering relationships;
- render and source stacks;
- cycle detection.

The frame is created for a top-level render and shared by all partials, layouts,
and views reached from that render. A later top-level render receives a new
frame, including when the same engine instance and compiled-template cache are
reused. Composition state must never leak between renders or survive an
exception.

## Typed View Resolution

### Uniform root and child behavior

A typed view object does not render itself and does not need a reference to the
engine. It supplies typed state and can optionally identify its template. The
engine resolves the object's template directly.

The root path:

```perl
my $page = MyApp::View::HTML::Contacts::List->new(
    list => $contacts,
);

my $html = $engine->render_view($page);
```

and the nested path:

```epl
%= view $self->navbar
```

use the same object-to-template resolution operation. Root views are not a
special untyped case; they can be ordinary pages, leaf views, or typed wrappers.

### Public configuration

The common case needs only template directories and a view namespace:

```perl
my $engine = Template::EmbeddedPerl->new(
    directories    => ['templates'],
    view_namespace => 'MyApp::View',
);
```

A logical nested view then expands by convention:

```text
HTML::Navbar
    -> MyApp::View::HTML::Navbar
    -> html/navbar.epl
```

`helpers` remains an independent engine option. A helper provides behavior to
templates; it does not construct views or choose their templates.

```perl
my $engine = Template::EmbeddedPerl->new(
    directories    => ['templates'],
    view_namespace => 'MyApp::View',
    helpers => {
        path_for => sub {
            my ($engine, $route, @args) = @_;
            return $router->path_for($route, @args);
        },
        format_money => sub {
            my ($engine, $amount) = @_;
            return $money->format($amount);
        },
    },
);
```

These helpers are available alongside `$self` in root views, nested views, typed
wrappers, layouts, and partials.

An optional `view_factory` callback replaces only logical-name construction:

```perl
my $engine = Template::EmbeddedPerl->new(
    directories    => ['templates'],
    view_namespace => 'MyApp::View',
    view_factory   => sub {
        my ($class, $args, $context) = @_;

        return $container->build(
            $class,
            %$args,
            root   => $context->root_view,
            parent => $context->view,
        );
    },
);
```

The callback receives the fully expanded class name, a hash reference containing
only arguments explicitly supplied by the template, and the existing render
context. It must return a blessed object. The returned object's class may differ
from the requested class so factories can return subclasses or adapters.

There is no public `view_resolver`, `build_view`, or `template_for` contract.
External template-selection policy is intentionally deferred until a concrete
need justifies another extension point.

### Template resolution

Object rendering first looks for a `template` method on the view. A nonempty
value is authoritative. If the method is absent or returns an empty value, the
engine uses its configured `view_namespace`: the namespace prefix is removed,
`::` becomes `/`, and every remaining TitleCase or CamelCase package segment is
converted to lowercase snake case. Acronym runs are kept together, so `HTML`,
`HTMLPage`, and `ContactList` become `html`, `html_page`, and `contact_list`.
The normal file loader adds the configured `template_extension`.

For example:

```perl
my $engine = Template::EmbeddedPerl->new(
    directories => [
        '/srv/myapp/templates',
        '/srv/theme/templates',
        '/srv/shared/templates',
    ],
    view_namespace => 'MyApp::View',
);
```

maps `MyApp::View::HTML::ContactList` to
`html/contact_list.epl`. Rendering an object with neither an explicit `template`
method nor a class beneath `view_namespace` fails with a clear resolution error.

A view object can explicitly override convention-based lookup with a method:

```perl
sub template { 'components/navigation' }
```

An explicit template identifier takes precedence over convention. If that
identifier cannot be loaded, rendering fails rather than falling back to the
conventional path. Resolution ultimately delegates loading and compilation to
the engine's normal file-template facilities so template directories,
extensions, caching, and source diagnostics continue to work.

Object-to-template resolution uses this fixed precedence:

1. A nonempty value returned by the view object's `template` method.
2. The configured `view_namespace` convention.
3. A source-aware resolution error.

After the default constructor or `view_factory` constructs a logical child,
that object enters this same object-to-template sequence. Logical and
preconstructed views therefore cannot drift into different template lookup
behavior.

### Template search path

The existing `directories` configuration is the template search path. It has
the same precedence behavior as the UNIX `PATH`: each directory is tested in
the declared order and the first matching template wins. Given the configuration
above, `html/contact_list.epl` is searched as:

```text
/srv/myapp/templates/html/contact_list.epl
/srv/theme/templates/html/contact_list.epl
/srv/shared/templates/html/contact_list.epl
```

This ordering lets an application override a theme or shared template without
copying the rest of that template tree. Explicit template identifiers,
convention-derived view identifiers, partials, layouts, and typed views all use
the same search path and priority rules. A missing-template error reports the
logical identifier and every candidate path in search order.

### Object construction

The core accepts both preconstructed objects and logical names:

```epl
%= view $self->navbar
%= view 'HTML::Navbar', active_link => 'contacts'
```

For a preconstructed object, the engine skips construction and performs only
template lookup. This applies to both `render_view($object)` and `view $object`;
neither invokes `view_factory`.

For a logical name, the engine validates that the value is a relative Perl
package name, prefixes `view_namespace`, loads the expanded class, and calls:

```perl
$class->new(%explicit_args)
```

Logical names require `view_namespace`. They cannot supply a fully qualified
class that bypasses the configured namespace. Class loading uses Perl's normal
package-to-file mapping. A class that already provides `new`, including a class
declared in the calling program or test file, is treated as loaded; otherwise
the engine requires its package file.

When configured, `view_factory` replaces the `new` call but not validation,
namespace expansion, class loading, object validation, or template selection.
The context lets an application inject relationships such as `root` and
`parent`; the default constructor never injects them implicitly.

Template::EmbeddedPerl does not mutate any constructed or preconstructed object
to add `root`, `parent`, or context. Application code must establish those
relationships during construction when its view model requires them.

The final code reference passed to `view` is the optional wrapper body. Arguments
before that callback must be an even-sized constructor list. A preconstructed
object accepts a wrapper callback but not constructor arguments; callers must
construct such an object with all required state before rendering it.

## Composition Semantics

### Partial

`partial` renders another template immediately within the current frame:

```epl
%= partial 'contacts/summary', contact => $self->contact
```

The partial inherits the caller's `$self`. Additional arguments remain ordinary
untyped template arguments and are available through the supported declarative
argument syntax or legacy `@_`. Partial output is a safe rendered value so it is
not escaped a second time when inserted with `%=`.

Partials cannot establish a new typed contract. A caller that needs a different
`$self` uses `view`.

### Layout

`layout` selects an untyped outer template for the current rendered body:

```epl
% layout 'layouts/application', title => 'Contacts'
```

The layout inherits the caller's `$self` and reads body and named content from
the current frame. Named arguments after the template identifier belong to the
layout template and are bound by its `args` declaration just like partial
arguments. Layouts can nest; each outer layout consumes the completed inner
result as its default content. The implementation defines deterministic ordering
so multiple declarations wrap in declaration order, with the first declared
layout outermost.

Layout recursion is detected and reported with the complete template stack.

### View

`view` renders a typed view as a leaf:

```epl
%= view 'HTML::Navbar', active_link => 'contacts'
```

or as a wrapper:

```epl
%= view 'HTML::Page', page_title => 'Contacts', sub ($page) {
  %= view 'HTML::Navbar', active_link => 'contacts'

  <main>
    <h1><%= $self->title %></h1>
  </main>
% }
```

For a wrapper, the engine constructs or accepts the wrapper view before
executing the body callback. The callback receives that object as its argument,
shown as `$page` above. Perl lexical scoping means `$self` inside the captured
body remains the calling view. When the wrapper template itself renders,
`$self` is the wrapper object.

This distinction permits the caller to contribute content using its own typed
contract while also inspecting the wrapper object when needed. Typed wrappers
can nest without a fixed depth and can contain partials, layouts, and other typed
views.

Like partial output, rendered view output is safe and is not escaped twice.

## Content Blocks

The frame provides a default content block and named content blocks. A layout or
typed wrapper consumes them using `yield`:

```epl
<head>
  %= yield 'css'
</head>
<body>
  %= yield
  %= yield 'js'
</body>
```

`yield` without a name returns the wrapper body. `yield 'name'` returns the
accumulated named content, or an empty safe string when no content exists.

Callers contribute named content with captured blocks:

```epl
% content_for css => sub {
  <link rel="stylesheet" href="/contacts.css">
% }
```

Repeated `content_for` calls append in render order, matching Rails-style
content accumulation. `content_replace` explicitly discards prior content for a
name before storing the replacement:

```epl
% content_replace title => sub {
  Contacts
% }
```

`has_content 'name'` reports whether a nonempty contribution exists. Captured
and yielded values preserve safe-string semantics. Named content uses the shared
frame, so a deeply nested partial or typed view can contribute CSS, JavaScript,
or metadata consumed by an outer wrapper.

A typed wrapper receives a scoped default body for its own `yield`. Named
content remains frame-wide. Nested wrappers must restore the previous default
body after rendering, including on exceptions.

## Template Arguments and `$self`

Typed templates treat `$self` as their primary data contract. Moo attributes
remain methods:

```epl
<h1><%= $self->title %></h1>
```

The engine will not generate local variables from Moo attributes, inspect a
Moo metaclass, or duplicate the class's required/type constraints in template
syntax.

A declarative `args` directive is available to untyped root templates, partials,
and layouts to reduce manual `shift` boilerplate:

```epl
% args $contact, $show_actions = 1

<h2><%= $contact->name %></h2>
```

Arguments are supplied as a named key/value list. A declaration without a
default is required; a declaration with `= expression` uses that expression when
the key is absent. Passing an explicit `undef` does not activate a default.
Defaults are evaluated at render time in declaration order and can reference
arguments declared earlier.

An anonymous-subroutine default is a lazy default factory for more complex
initialization:

```epl
% args $contacts, $title = sub {
%   my $count = @$contacts;
%   return $count == 1 ? 'One contact' : "$count contacts";
% }
```

The factory runs once only when its argument is absent, and its return value is
assigned to the argument. Odd argument lists, missing required arguments,
duplicate keys, and unknown keys produce source-aware errors. The directive must
be the first executable directive in its template and can occur only once.

`args` binds only the explicit argument list passed to that template. It never
reads view attributes or creates aliases for Moo methods. Constructor arguments
passed to a logical `view` call are consumed by the view constructor and are
not also passed to the rendered view template. Legacy access through `@_`,
`shift`, and configured `prepend` continues to work in templates that do not opt
into `args`.

Because existing callers can intentionally pass a blessed value as the first
argument, only `render_view` and `view` establish a typed `$self`. Existing
`render` never infers one.

## Smart Line Directives

Line directives support code and expressions without explicit tags:

```epl
% if ($self->has_contacts) {
  <p>Contacts available</p>
% }

%= partial 'contacts/summary', contact => $self->contact
```

When `%` or `%=` is the first non-whitespace token on a line, its indentation and
line ending are syntax rather than output. This removes the need for trailing
backslashes or trim markers around ordinary control flow and composition calls.
Literal lines that do not begin with a directive retain their whitespace.

This whitespace behavior is enabled with `smart_lines => 1`. It is opt-in for
the first release so existing templates that depend on line-directive newlines
remain byte-for-byte compatible. Existing tag syntax, legacy line behavior, and
explicit trim behavior remain supported. Tests must cover both modes, Unix and
Windows line endings, blank lines, nested blocks, multiline Perl, literal percent
characters, and files without a final newline.

## Helper and Escaping Context

Existing helper callbacks continue to receive the rendering engine/context
contract they use today; introducing `$self` must not silently replace the
helper receiver with a view object.

When an expression value implements `to_safe_string`, typed rendering passes the
active view object as its contextual argument. Legacy rendering continues to
pass the engine as before. This lets framework values use request/view context
without breaking existing untyped templates.

Output produced by `partial`, `layout`, `view`, `yield`, `content_for`, and
`content_replace` is represented with the engine's safe-string mechanism.
Ordinary expression values remain subject to the configured auto-escaping rules.

## Errors and Diagnostics

Composition failures include the logical operation and complete source stack.
The implementation must distinguish at least:

- invalid logical view names;
- logical view names used without `view_namespace`;
- class-loading failures that identify both logical and expanded names;
- a default constructor failure, including Moo required/type constraint errors;
- a `view_factory` exception;
- a `view_factory` returning an unblessed value;
- a preconstructed object outside `view_namespace` with no explicit template;
- a missing template for a resolved view;
- recursive partial, layout, or view rendering;
- runtime failures inside a nested template or captured body.

Errors preserve the existing source-line diagnostics and add the chain of
templates/views that led to the failure. Cleanup is exception-safe: active
renderer state, default bodies, named content, and render stacks are restored or
discarded before the exception escapes. A missing-template error includes the
derived or explicit identifier and every configured candidate path in priority
order. Constructor and factory errors retain the original exception text.

## Compatibility

Relative to the released API, this feature is additive:

- Existing `render($template, @args)` behavior is unchanged.
- Existing compiled objects still support `render(@args)`.
- Existing templates using tags, `@_`, `shift`, `prepend`, custom helpers, and
  block capture continue to work.
- Blessed legacy arguments are never treated as views implicitly.
- Moo is a test/development dependency for examples, not a runtime dependency.
- Applications can use convention-based logical construction, replace
  construction with `view_factory`, or render preconstructed objects.
- The unreleased `view_resolver`, `build_view`, and `template_for` interfaces are
  removed without a compatibility shim.

## Test Strategy

Coverage will be organized around public behavior rather than internal classes.

### Typed view tests

Tests define small local Moo classes and construct real instances. Cases include:

- rendering a typed root view through `render_view`;
- required Moo attributes, defaults, coercion/type failures, constructor
  exceptions, and method access through `$self`;
- TitleCase/CamelCase-to-snake-case convention lookup, including acronym runs;
- explicit `template` lookup, precedence, and no fallback after an explicit
  template fails to load;
- first-match template search across multiple configured directories;
- fallback to lower-priority template directories and complete missing paths;
- a preconstructed nested view;
- a logical nested view constructed by default through `new`;
- a `view_factory` receiving the expanded class, explicit arguments, and current
  render context;
- a `view_factory` injecting `root` and `parent` across multiple nesting levels;
- preconstructed objects bypassing `view_factory`;
- invalid logical names, missing namespace, class-loading errors, and unblessed
  factory results;
- a typed leaf view;
- a typed wrapper whose callback receives the wrapper object;
- lexical caller `$self` in a wrapper body and wrapper `$self` in its template;
- multiple and arbitrarily nested typed wrappers;
- a typed root that is itself a wrapper;
- Moo constructor/type errors with render-stack diagnostics;
- no state leakage when the engine renders multiple view trees.

### Composition tests

Cases include:

- partial arguments and inherited `$self`;
- one and multiple nested layouts;
- deterministic layout ordering;
- default `yield` and empty default content;
- named content append ordering;
- `content_replace` and `has_content`;
- named contributions from nested partials and views;
- scoped default bodies across nested wrappers;
- recursive partial, layout, and view errors;
- source stacks for nested compile and runtime failures;
- exception-safe frame cleanup.

### Compatibility and output safety tests

Cases include:

- all existing tests remaining green;
- legacy objects in `@_` not becoming `$self`;
- `shift`, `@_`, and `prepend` inside existing templates;
- custom helpers retaining their engine/context receiver;
- helpers used from typed roots, nested views, typed wrappers, layouts, and
  partials;
- typed and legacy `to_safe_string` context behavior;
- no double escaping for partials, views, layouts, and yields;
- ordinary values remaining escaped when auto-escaping is enabled;
- legacy and smart line whitespace behavior across line endings and edge cases;
- named `args`, expression and lazy-subroutine defaults, `undef`, validation
  errors, and isolation from Moo attributes;
- named arguments passed independently to layouts and partials.

## Documentation

The public documentation will include a cookbook section that builds and renders
a small Moo view class. It will show:

1. A typed root page constructed by application/framework code.
2. The snake-case class-to-template convention, ordered template search path,
   and an explicit `template` override.
3. A logical Moo child view constructed automatically through `new`.
4. A preconstructed child view.
5. A `view_factory` dependency-injection example using the class, explicit
   arguments, and render context.
6. A typed wrapper with injected `root` and `parent` relationships.
7. Nested wrappers and named CSS/JavaScript content.
8. Equivalent simple `partial` and `layout` examples for cases where a class is
   unnecessary.

The cookbook will state clearly that Moo is illustrative, any blessed object can
serve as a typed view, default logical construction is ordinary `new`, and
applications can take responsibility for construction with `view_factory` when
needed.

## Delivery Boundaries

Implementation should proceed in layers that remain testable:

1. Render context/frame and explicit `render_view` support.
2. Object-to-template resolution and convention-based logical construction.
3. `partial`, `layout`, and `view` composition.
4. Default/named content blocks and nesting cleanup.
5. Smart line directives and declarative untyped arguments.
6. Error-stack integration, compatibility hardening, and documentation.

The implementation plan can split these layers further, but it must not add a
Moo runtime dependency, inject undeclared constructor arguments, add external
template-selection policy, or create different resolution rules for root and
nested typed views.
