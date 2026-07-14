# Typed View Composition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add low-ceremony named arguments, smart lines, partials, layouts, content blocks, and uniformly resolved typed root/nested views without breaking legacy templates.

**Architecture:** Keep parsing, compilation, template loading, helpers, and escaping on `Template::EmbeddedPerl`; introduce request-local `RenderContext` and `RenderFrame` objects for nested rendering and composition state. Compile an explicit context parameter ahead of legacy `@_`, use one ordered file lookup path for every template kind, and delegate logical typed-view construction to an optional framework resolver.

**Tech Stack:** Perl, PPI, Moo in tests only, Test::Most, File::Spec, File::Temp, existing `Template::EmbeddedPerl::SafeString` APIs.

## Global Constraints

- Preserve `render($template, @args)`, `from_string`, `from_file`, `from_fh`, `from_data`, `Compiled->render(@args)`, `@_`, `shift`, `prepend`, existing helpers, and existing tag syntax.
- Never infer a typed view from a blessed argument passed through a legacy render API; only `render_view` and `view` establish `$self`.
- Keep Moo out of runtime prerequisites; add it only under `on test` in `cpanfile`.
- Keep `smart_lines` disabled by default; legacy line-directive output must remain byte-for-byte compatible.
- Resolve both root and nested typed view objects with the same precedence: object `template`, resolver `template_for`, then `view_namespace` convention.
- Convert each package suffix segment from TitleCase/CamelCase to lowercase snake_case, preserving acronym runs: `HTML` -> `html`, `HTMLPage` -> `html_page`, `ContactList` -> `contact_list`.
- Treat `directories` as an ordered UNIX-`PATH`-style search list; first matching template wins for roots, views, layouts, and partials.
- Create a fresh render frame for every top-level render and share it only with nested work reached from that render.
- Return nested template output through `Template::EmbeddedPerl::SafeString` so composition never double escapes output.
- Preserve source-aware compile/runtime diagnostics and add a single render stack for nested failures.
- Follow TDD for every task: observe the targeted test fail before implementing, then run the targeted file and full suite before committing.

---

## File Map

- Create `lib/Template/EmbeddedPerl/RenderContext.pm`: immutable render scope carrying engine, frame, current view, root view, and source.
- Create `lib/Template/EmbeddedPerl/RenderFrame.pm`: mutable per-render stacks for active templates, layouts, default bodies, and named content.
- Create `lib/Template/EmbeddedPerl/Arguments.pm`: parse and rewrite the compile-time `args` directive into lexical named-argument bindings.
- Modify `lib/Template/EmbeddedPerl.pm`: configuration, helper dispatch, smart-line parsing, lookup, composition helpers, view resolution, and public `render_view`.
- Modify `lib/Template/EmbeddedPerl/Compiled.pm`: create/reuse contexts and preserve legacy arguments while rendering compiled code.
- Modify `lib/Template/EmbeddedPerl/Utils.pm`: format nested render-stack diagnostics once.
- Modify `lib/Template/EmbeddedPerl/SafeString.pm` only if focused tests expose a missing safe concatenation primitive; otherwise leave it unchanged.
- Create `t/render_context.t`: legacy compatibility and render-frame lifetime.
- Create `t/smart_lines.t`: opt-in directive whitespace behavior.
- Create `t/args.t`: required/default/lazy named arguments and validation.
- Create `t/template_lookup.t`: ordered directories and class-to-template conversion.
- Create `t/partial.t`: untyped partial behavior and escaping.
- Create `t/layout.t`: layout arguments, yields, nesting, and ordering.
- Create `t/content_blocks.t`: named content append/replace/query behavior.
- Create `t/typed_view.t`: real Moo root, child, leaf, and wrapper views.
- Create `t/composition_errors.t`: cycles, nested source stacks, and exception cleanup.
- Create fixtures under `t/templates/composition/` and `t/templates/views/` only when a file-backed behavior cannot be expressed clearly with a temporary directory.
- Modify `cpanfile`: add Moo as a test prerequisite.
- Modify `lib/Template/EmbeddedPerl.pm` POD, `README.mkdn`, and `Changes`: public API and cookbook documentation.

---

### Task 1: Add Render Context and Frame Plumbing

**Files:**
- Create: `lib/Template/EmbeddedPerl/RenderContext.pm`
- Create: `lib/Template/EmbeddedPerl/RenderFrame.pm`
- Modify: `lib/Template/EmbeddedPerl.pm:19,134-228,232-273,493-498`
- Modify: `lib/Template/EmbeddedPerl/Compiled.pm:1-25`
- Test: `t/render_context.t`
- Test: `t/regressions.t`

**Interfaces:**
- Produces: `Template::EmbeddedPerl::RenderContext->new(engine => $engine, frame => $frame, view => $view, root_view => $root, source => $source)`.
- Produces: context readers `engine`, `frame`, `view`, `root_view`, `source`, and clone method `with(%overrides)`.
- Produces: `Template::EmbeddedPerl::RenderFrame->new`, `push_render(%entry)`, `pop_render`, `current_scope`, and `render_stack`.
- Produces: `Template::EmbeddedPerl->_new_render_context(%args)` and `Compiled->_render_with_context($context, $entry, @args)` for later tasks, where `$entry` contains `kind`, `identifier`, and `source`.

- [ ] **Step 1: Write failing context and legacy-argument tests**

```perl
use Test::Most;
use Template::EmbeddedPerl;
use Template::EmbeddedPerl::RenderContext;

my $engine = Template::EmbeddedPerl->new(
    prepend => 'my $prepended = shift;',
);

is(
    $engine->from_string('<%= $prepended %>:<%= shift %>')->render('first', 'second'),
    'first:second',
    'context argument is hidden from prepend, shift, and legacy @_',
);

my $first = $engine->_new_render_context;
my $second = $engine->_new_render_context;
isnt($first->frame, $second->frame, 'top-level contexts never share frames');

my $view = bless {}, 'Local::View';
my $child = $first->with(view => $view, source => 'child.epl');
is($child->engine, $first->engine, 'child keeps engine');
is($child->frame, $first->frame, 'child shares frame');
is($child->view, $view, 'child changes current view');
is($child->source, 'child.epl', 'child changes source');

done_testing;
```

- [ ] **Step 2: Run the test to verify the missing context fails**

Run: `prove -lv t/render_context.t`

Expected: FAIL because `Template/EmbeddedPerl/RenderContext.pm` does not exist.

- [ ] **Step 3: Implement the two state objects**

```perl
package Template::EmbeddedPerl::RenderContext;

use strict;
use warnings;

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

1;
```

```perl
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
```

- [ ] **Step 4: Pass context separately to generated template code**

Change `compiled` to generate this wrapper shape:

```perl
sub {
    my $__context = shift;
    my $_O = '';
    my $self = $__context->view;
    # existing prepend and compiled body follow; @_ now contains only legacy args
    return $_O;
}
```

Change `Compiled` to create a context only for a public top-level render and to localize the active context during nested renders:

```perl
sub render {
    my ($self, @args) = @_;
    my $context = $self->{yat}->_new_render_context(source => $self->{source});
    my $entry = {
        kind => 'root',
        identifier => $self->{identifier} || $self->{source} || '<string>',
        source => $self->{source},
    };
    return $self->_render_with_context($context, $entry, @args);
}

sub _render_with_context {
    my ($self, $context, $entry, @args) = @_;
    local $Template::EmbeddedPerl::ACTIVE_RENDERER = $context;
    return $self->{code}->($context, @args);
}
```

Update injected helper dispatch so custom/default helpers still receive the engine, not the view or context:

```perl
my $context = Template::EmbeddedPerl->_current_render_context('$helper');
my $engine = $context->engine;
$engine->get_helpers('$helper')->($engine, @_);
```

- [ ] **Step 5: Run focused compatibility tests**

Run: `prove -lv t/render_context.t t/regressions.t t/stringification.t`

Expected: PASS; nested helper engines restore correctly and legacy `shift` remains unchanged.

- [ ] **Step 6: Run the full suite**

Run: `prove -lr t`

Expected: PASS with at least the existing 142 assertions plus `t/render_context.t`.

- [ ] **Step 7: Commit**

```bash
git add lib/Template/EmbeddedPerl.pm lib/Template/EmbeddedPerl/Compiled.pm lib/Template/EmbeddedPerl/RenderContext.pm lib/Template/EmbeddedPerl/RenderFrame.pm t/render_context.t
git commit -m "Add request-local template render contexts"
```

---

### Task 2: Add Opt-in Smart Line Directives

**Files:**
- Modify: `lib/Template/EmbeddedPerl.pm:134-153,331-448`
- Create: `t/smart_lines.t`
- Test: `t/newline_trim.t`
- Test: `t/regressions.t`

**Interfaces:**
- Consumes: existing `parse_template($template)` and configurable `line_start`/`expr_marker`.
- Produces: constructor option `smart_lines => 0|1`, default `0`.
- Produces: code/expression directive lines that consume indentation and their line ending only when enabled.

- [ ] **Step 1: Write the failing smart-line matrix**

```perl
use Test::Most;
use Template::EmbeddedPerl;

my $legacy = Template::EmbeddedPerl->new;
my $smart = Template::EmbeddedPerl->new(smart_lines => 1);

my $template = "% my \$show = 1\n% if (\$show) {\n  <p>Shown</p>\n% }\n";
is($legacy->from_string($template)->render, "\n\n  <p>Shown</p>\n\n", 'legacy mode preserves directive newlines');
is($smart->from_string($template)->render, "  <p>Shown</p>\n", 'smart mode consumes directive lines');
is($smart->from_string("%= uc 'ok'\n")->render, 'OK', 'smart expression consumes its newline');
is($smart->from_string("%= uc 'ok'")->render, 'OK', 'smart expression works without final newline');
is($smart->from_string("\\% literal\n")->render, "% literal\n", 'escaped percent remains literal');
is($smart->from_string("  100% complete\n")->render, "  100% complete\n", 'non-leading percent remains text');
is($smart->from_string("% my \$x = 1\r\n<p><%= \$x %></p>\r\n")->render, "<p>1</p>\n", 'CRLF input normalizes and trims');

done_testing;
```

- [ ] **Step 2: Run the test to verify legacy parsing fails smart expectations**

Run: `prove -lv t/smart_lines.t`

Expected: FAIL because `smart_lines` does not change directive newline output.

- [ ] **Step 3: Add `smart_lines` and consume complete directive lines**

Add `smart_lines => 0` to constructor defaults. In `parse_template`, branch the line rewrite before generic segment splitting:

```perl
if ($self->{smart_lines}) {
    $template =~ s{
        ^[\t ]*\Q${line_start}${expr_marker}\E(.*?)(?:\n|\z)
    }{${open_tag}${expr_marker}$1${close_tag}}mgx;
    $template =~ s{
        ^[\t ]*(?!\Q${close_tag}\E[\t ]*$)\Q${line_start}\E(.*?)(?:\n|\z)
    }{${open_tag}$1${close_tag}}mgx;
} else {
    # retain the two existing substitutions exactly
}
```

Keep escaped line-start processing after both branches. Do not alter tag-based trim handling.

- [ ] **Step 4: Run smart-line and legacy newline tests**

Run: `prove -lv t/smart_lines.t t/newline_trim.t t/regressions.t`

Expected: PASS in both modes, including custom regex-metacharacter line markers.

- [ ] **Step 5: Run the full suite**

Run: `prove -lr t`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/Template/EmbeddedPerl.pm t/smart_lines.t
git commit -m "Add opt-in smart template lines"
```

---

### Task 3: Compile Declarative Named Arguments

**Files:**
- Create: `lib/Template/EmbeddedPerl/Arguments.pm`
- Modify: `lib/Template/EmbeddedPerl.pm:10-17,232-273,450-498`
- Modify: `lib/Template/EmbeddedPerl/RenderContext.pm`
- Create: `t/args.t`

**Interfaces:**
- Produces: `% args $required, $optional = expression` as the first executable directive.
- Produces: `% args $required, $optional = sub { ... }` where the anonymous sub is invoked lazily once when absent.
- Produces internal `Arguments->rewrite($template)` returning `($rewritten_template, $has_args)`.
- Produces context methods `named_arguments(\@args)`, `take_required_argument`, `take_optional_argument`, and `assert_no_arguments`.

- [ ] **Step 1: Write failing required/default/lazy argument tests**

```perl
use Test::Most;
use Template::EmbeddedPerl;

my $engine = Template::EmbeddedPerl->new(smart_lines => 1);

my $compiled = $engine->from_string(<<'EPL');
% args $name, $greeting = 'Hello'
<%= $greeting %>, <%= $name %>!
EPL
is($compiled->render(name => 'Jane'), 'Hello, Jane!\n', 'expression default is used');
is($compiled->render(name => 'Jane', greeting => 'Hi'), 'Hi, Jane!\n', 'default is overridden');

my $lazy = $engine->from_string(<<'EPL');
% args $items, $title = sub {
%   my $count = @$items;
%   return $count == 1 ? 'One item' : "$count items";
% }
<%= $title %>
EPL
is($lazy->render(items => [1, 2]), "2 items\n", 'lazy factory can use an earlier argument');
is($lazy->render(items => [], title => undef), "\n", 'explicit undef does not use default');

throws_ok { $compiled->render } qr/Missing required template argument 'name'/;
throws_ok { $compiled->render(name => 'Jane', extra => 1) } qr/Unknown template argument 'extra'/;
throws_ok { $compiled->render(name => 'Jane', name => 'John') } qr/Duplicate template argument 'name'/;
throws_ok { $compiled->render(name => 'Jane', 'odd') } qr/Odd template argument list/;
throws_ok {
    $engine->from_string("text\n% args \$name\n");
} qr/args must be the first executable directive/;

done_testing;
```

- [ ] **Step 2: Run the test to verify `args` is parsed as an undefined subroutine**

Run: `prove -lv t/args.t`

Expected: FAIL at compile time because `args` is not defined and no lexicals are generated.

- [ ] **Step 3: Implement argument directive extraction and code generation**

Implement `Arguments->rewrite` as a source-preserving pre-pass before `parse_template`:

1. Accept comments/blank lines before `args`, reject prior executable text or code.
2. Collect the initial `% args` line and following `%` lines until PPI reports balanced parentheses/braces/brackets and the declaration no longer ends in a comma/operator.
3. Split declarations on top-level commas using PPI structures, accepting only scalar symbols with an optional top-level `=` default.
4. Replace the whole directive span with one `<% ... -%>` code block whose internal newlines preserve source line count.

Generate bindings in declaration order:

```perl
my $__named_args = $__context->named_arguments(\@_);
my $name = $__context->take_required_argument($__named_args, 'name');
my $greeting = $__context->take_optional_argument(
    $__named_args,
    'greeting',
    sub { 'Hello' },
);
$__context->assert_no_arguments($__named_args);
```

For a syntactic anonymous-sub default, pass that sub directly instead of wrapping it in another sub. For any other expression, wrap it in `sub { EXPR }`.

- [ ] **Step 4: Implement runtime named-list validation**

```perl
sub named_arguments {
    my ($self, $args) = @_;
    die "Odd template argument list\n" if @$args % 2;
    my @copy = @$args;
    my %named;
    while (@copy) {
        my ($name, $value) = splice @copy, 0, 2;
        die "Duplicate template argument '$name'\n" if exists $named{$name};
        $named{$name} = $value;
    }
    return \%named;
}

sub take_required_argument {
    my ($self, $named, $name) = @_;
    die "Missing required template argument '$name'\n" unless exists $named->{$name};
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
    die "Unknown template argument '$_'\n" for @unknown;
    return;
}
```

`assert_no_arguments` sorts remaining keys and reports each unknown key deterministically. Copy `@_` before validation so the generated template's localized legacy `@_` remains available for diagnostics and compatibility outside templates opting into `args`.

- [ ] **Step 5: Run argument tests and source-diagnostic regressions**

Run: `prove -lv t/args.t t/regressions.t t/newline_trim.t`

Expected: PASS; errors mention the supplied `source` and correct template line.

- [ ] **Step 6: Run the full suite**

Run: `prove -lr t`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/Template/EmbeddedPerl.pm lib/Template/EmbeddedPerl/Arguments.pm lib/Template/EmbeddedPerl/RenderContext.pm t/args.t
git commit -m "Add declarative named template arguments"
```

---

### Task 4: Unify Ordered Template and View Path Resolution

**Files:**
- Modify: `lib/Template/EmbeddedPerl.pm:134-153,309-327`
- Create: `t/template_lookup.t`

**Interfaces:**
- Produces: `_template_candidates($identifier) -> @paths`.
- Produces: `_resolve_template_file($identifier) -> $first_existing_path`.
- Produces: `_class_to_template($class) -> $identifier` using configured `view_namespace`.
- Produces: `_template_for_view($view, $context) -> $identifier` with spec-defined precedence.
- Preserves: nested-array directory components already accepted by `directories`.

- [ ] **Step 1: Write failing ordered-lookup and snake-case tests**

Use `File::Temp::tempdir`, create `app/html/contact_list.epl` and `shared/html/contact_list.epl`, then assert:

```perl
is(
    $engine->_class_to_template('MyApp::View::HTML::ContactList'),
    'html/contact_list',
    'package suffix becomes a snake-case template identifier',
);
is($engine->_class_to_template('MyApp::View::HTMLPage'), 'html_page', 'acronym run stays together');
is($engine->from_file('html/contact_list')->render, 'app', 'first matching directory wins');
unlink $app_template;
is($engine->from_file('html/contact_list')->render, 'shared', 'lookup falls back in order');
```

Add view classes with `template` methods and a resolver whose `template_for` returns a different value; assert object `template` wins, resolver is second, and convention is third. Assert a missing-template error lists every candidate path in declared order.

- [ ] **Step 2: Run lookup tests to verify missing APIs fail**

Run: `prove -lv t/template_lookup.t`

Expected: FAIL because class conversion and candidate APIs do not exist and missing errors do not list candidates.

- [ ] **Step 3: Extract ordered file lookup from `from_file`**

```perl
sub _template_candidates {
    my ($self, $identifier) = @_;
    my $file = "$identifier.$self->{template_extension}";
    return map { File::Spec->catfile(ref($_) eq 'ARRAY' ? File::Spec->catdir(@$_) : $_, $file) }
        @{$self->{directories}};
}

sub _resolve_template_file {
    my ($self, $identifier) = @_;
    my @candidates = $self->_template_candidates($identifier);
    return $_ for grep { -e $_ } @candidates;
    die "Template '$identifier' not found; searched: " . join(', ', @candidates) . "\n";
}
```

Make `from_file` call `_resolve_template_file`, pass both `source => $path` and `identifier => $identifier` into the compiled object, and retain first-match behavior.

- [ ] **Step 4: Implement class segment conversion and view precedence**

```perl
sub _snake_case_segment {
    my ($self, $segment) = @_;
    $segment =~ s/([A-Z]+)([A-Z][a-z])/$1_$2/g;
    $segment =~ s/([a-z0-9])([A-Z])/$1_$2/g;
    return lc $segment;
}
```

Strip exactly `view_namespace . '::'`, split the suffix on `::`, map `_snake_case_segment`, and join with `/`. Reject classes outside the namespace. `_template_for_view` checks nonempty object `template`, then nonempty resolver `template_for($view, $context)`, then convention, and otherwise throws a resolution error naming the class.

- [ ] **Step 5: Run lookup and existing file tests**

Run: `prove -lv t/template_lookup.t t/regressions.t t/ff.t`

Expected: PASS; existing nested-array directories still work.

- [ ] **Step 6: Run the full suite**

Run: `prove -lr t`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/Template/EmbeddedPerl.pm t/template_lookup.t
git commit -m "Unify ordered template path resolution"
```

---

### Task 5: Render Untyped Partials

**Files:**
- Modify: `lib/Template/EmbeddedPerl.pm:208-228,309-327`
- Modify: `lib/Template/EmbeddedPerl/Compiled.pm`
- Modify: `lib/Template/EmbeddedPerl/RenderContext.pm`
- Modify: `lib/Template/EmbeddedPerl/RenderFrame.pm`
- Create: `t/partial.t`
- Create: `t/templates/composition/contacts/item.epl`

**Interfaces:**
- Produces: template helper `partial($identifier, @named_args) -> SafeString`.
- Produces: context method `render_file($kind, $identifier, @args)`.
- Produces: compiled metadata `identifier` used for render stacks and cycles.
- Guarantees: partial inherits current `view`, `root_view`, and frame.

- [ ] **Step 1: Add a failing partial integration test**

Fixture `t/templates/composition/contacts/item.epl`:

```epl
% args $contact
<li><%= $contact->{name} %></li>
```

Test:

```perl
my $engine = Template::EmbeddedPerl->new(
    directories => ['t/templates/composition'],
    smart_lines => 1,
    auto_escape => 1,
);
my $page = $engine->from_string(<<'EPL');
<ul>
%= partial 'contacts/item', contact => {name => '<Jane>'}
</ul>
EPL
is($page->render, "<ul>\n<li>&lt;Jane&gt;</li>\n</ul>\n", 'partial is escaped once');
```

Add cases for required/unknown partial args, inherited current view using a manually created context, and missing partial diagnostics.

- [ ] **Step 2: Run the test to verify `partial` is unavailable**

Run: `prove -lv t/partial.t`

Expected: FAIL with an undefined `partial` helper.

- [ ] **Step 3: Add nested file rendering to context and compiled objects**

`RenderContext->render_file` loads with the same engine and calls `_render_with_context` on a context clone with the compiled source. `Compiled->_render_with_context` pushes `{kind, identifier, source, view}` before running code and pops it in a `finally`-style eval cleanup. Keep the scope active while applying later layouts.

```perl
sub render_file {
    my ($self, $kind, $identifier, @args) = @_;
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
```

- [ ] **Step 4: Register the partial helper**

```perl
partial => sub {
    my ($engine, $identifier, @args) = @_;
    my $context = Template::EmbeddedPerl->_current_render_context('partial');
    my $output = $context->render_file('partial', $identifier, @args);
    return $engine->raw($output);
},
```

Validate a defined non-reference identifier and let the target template's `args` directive validate its named list.

- [ ] **Step 5: Run partial, escaping, and context tests**

Run: `prove -lv t/partial.t t/render_context.t t/stringification.t`

Expected: PASS with no double escaping.

- [ ] **Step 6: Run the full suite**

Run: `prove -lr t`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/Template/EmbeddedPerl.pm lib/Template/EmbeddedPerl/Compiled.pm lib/Template/EmbeddedPerl/RenderContext.pm lib/Template/EmbeddedPerl/RenderFrame.pm t/partial.t t/templates/composition/contacts/item.epl
git commit -m "Add untyped template partials"
```

---

### Task 6: Add Layouts and Default Yield

**Files:**
- Modify: `lib/Template/EmbeddedPerl.pm:208-228`
- Modify: `lib/Template/EmbeddedPerl/Compiled.pm`
- Modify: `lib/Template/EmbeddedPerl/RenderFrame.pm`
- Create: `t/layout.t`
- Create: `t/templates/composition/layouts/application.epl`
- Create: `t/templates/composition/layouts/outer.epl`
- Create: `t/templates/composition/layouts/inner.epl`

**Interfaces:**
- Produces: `layout($identifier, @named_args)` registering on the current render scope.
- Produces: `yield()` returning the current default body as a safe string.
- Produces frame methods `register_layout`, `take_layouts`, `with_body($body, $callback)`, and `default_body`.
- Guarantees: first declared layout is outermost; layout arguments are independent named args.

- [ ] **Step 1: Write failing single/nested layout tests**

Application fixture:

```epl
% args $title
<!doctype html><title><%= $title %></title><body><%= yield %></body>
```

Test page:

```epl
% layout 'layouts/application', title => 'Contacts'
<main>Contacts</main>
```

Assert exact output. Add outer/inner fixtures that output `outer(<%= yield %>)` and `inner(<%= yield %>)`; declare outer then inner and assert `outer(inner(body))`. Add a layout with `% args $title = 'Default'` and assert both default and override behavior.

- [ ] **Step 2: Run the test to verify helpers are unavailable**

Run: `prove -lv t/layout.t`

Expected: FAIL because `layout` and `yield` are undefined.

- [ ] **Step 3: Add scoped layout/body state**

```perl
sub register_layout {
    my ($self, $identifier, @args) = @_;
    push @{$self->current_scope->{layouts}}, [$identifier, \@args];
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

sub default_body { defined $_[0]->{default_body} ? $_[0]->{default_body} : '' }
```

After compiled body execution, take that scope's layouts and apply them in reverse declaration order while the current scope remains active:

```perl
for my $layout (reverse @$layouts) {
    my ($identifier, $args) = @$layout;
    $output = $frame->with_body($output, sub {
        $context->render_file('layout', $identifier, @$args);
    });
}
```

- [ ] **Step 4: Register layout and yield helpers**

```perl
layout => sub {
    my ($engine, $identifier, @args) = @_;
    Template::EmbeddedPerl->_current_render_context('layout')->frame
        ->register_layout($identifier, @args);
    return;
},
yield => sub {
    my ($engine) = @_;
    my $frame = Template::EmbeddedPerl->_current_render_context('yield')->frame;
    return $engine->raw($frame->default_body);
},
```

- [ ] **Step 5: Run layout and partial tests**

Run: `prove -lv t/layout.t t/partial.t`

Expected: PASS; first declaration is outermost and layout args bind independently.

- [ ] **Step 6: Run the full suite**

Run: `prove -lr t`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/Template/EmbeddedPerl.pm lib/Template/EmbeddedPerl/Compiled.pm lib/Template/EmbeddedPerl/RenderFrame.pm t/layout.t t/templates/composition/layouts
git commit -m "Add nested layouts and default yield"
```

---

### Task 7: Add Rails-style Named Content Blocks

**Files:**
- Modify: `lib/Template/EmbeddedPerl.pm:208-228`
- Modify: `lib/Template/EmbeddedPerl/RenderFrame.pm`
- Create: `t/content_blocks.t`
- Create: `t/templates/composition/layouts/slots.epl`

**Interfaces:**
- Produces: `content_for($name, $callback)`, `content_replace($name, $callback)`, `has_content($name)`, and `yield($name)`.
- Produces frame methods `append_content`, `replace_content`, `has_content`, and `content`.
- Guarantees: named content is frame-wide and appends in render order; default bodies remain dynamically scoped.

- [ ] **Step 1: Write failing append/replace/nesting tests**

```perl
my $template = $engine->from_string(<<'EPL');
% layout 'layouts/slots'
% content_for css => sub {
  <link href="one.css">
% }
% content_for css => sub {
  <link href="two.css">
% }
<main>Body</main>
EPL
```

The slots layout yields `css`, the default body, and optional `js`. Assert CSS contributions append in call order, absent JS is an empty safe string, `has_content 'css'` is true, and `content_replace css => sub { ... }` discards both earlier contributions. Add a nested partial contribution and assert the outer layout receives it.

- [ ] **Step 2: Run the test to verify named helpers are unavailable**

Run: `prove -lv t/content_blocks.t`

Expected: FAIL because `content_for`, `content_replace`, and `has_content` are undefined and `yield` ignores names.

- [ ] **Step 3: Add frame-wide named storage**

```perl
sub append_content {
    my ($self, $name, $value) = @_;
    push @{$self->{named_content}{$name}}, $value;
}

sub replace_content {
    my ($self, $name, $value) = @_;
    $self->{named_content}{$name} = [$value];
}

sub content {
    my ($self, $name) = @_;
    return join '', @{$self->{named_content}{$name} || []};
}

sub has_content {
    my ($self, $name) = @_;
    return length $self->content($name) ? 1 : 0;
}
```

- [ ] **Step 4: Register capture helpers and named yield**

Each capture helper requires a string name and code reference, invokes the callback exactly once, and stores its safe captured output. `yield()` reads `default_body`; `yield($name)` reads named content. Wrap both with `$engine->raw`.

```perl
content_for => sub {
    my ($engine, $name, $callback) = @_;
    my $frame = Template::EmbeddedPerl->_current_render_context('content_for')->frame;
    $frame->append_content($name, $callback->());
    return;
},
content_replace => sub {
    my ($engine, $name, $callback) = @_;
    my $frame = Template::EmbeddedPerl->_current_render_context('content_replace')->frame;
    $frame->replace_content($name, $callback->());
    return;
},
has_content => sub {
    my ($engine, $name) = @_;
    return Template::EmbeddedPerl->_current_render_context('has_content')->frame
        ->has_content($name);
},
yield => sub {
    my ($engine, @args) = @_;
    my $frame = Template::EmbeddedPerl->_current_render_context('yield')->frame;
    my $output = @args ? $frame->content($args[0]) : $frame->default_body;
    return $engine->raw($output);
},
```

- [ ] **Step 5: Run content, layout, partial, and escaping tests**

Run: `prove -lv t/content_blocks.t t/layout.t t/partial.t t/stringification.t`

Expected: PASS with ordered accumulation and no double escaping.

- [ ] **Step 6: Run the full suite**

Run: `prove -lr t`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/Template/EmbeddedPerl.pm lib/Template/EmbeddedPerl/RenderFrame.pm t/content_blocks.t t/templates/composition/layouts/slots.epl
git commit -m "Add named template content blocks"
```

---

### Task 8: Render Typed Root Views

**Files:**
- Modify: `lib/Template/EmbeddedPerl.pm:134-153,208-228,597-601`
- Modify: `lib/Template/EmbeddedPerl/RenderContext.pm`
- Modify: `lib/Template/EmbeddedPerl/Compiled.pm`
- Modify: `cpanfile`
- Create: `t/typed_view.t`
- Create: `t/templates/views/html/contacts/index.epl`
- Create: `t/templates/views/components/navigation.epl`

**Interfaces:**
- Produces public `render_view($view) -> $output`.
- Consumes `_template_for_view($view, $context)` from Task 4.
- Produces context method `render_view_object($view)` used by root and nested paths.
- Guarantees: root context has `view == root_view == $view`; typed compiled templates receive lexical `$self`.

- [ ] **Step 1: Add Moo as a test-only dependency and write root tests**

Add under `on test` in `cpanfile`:

```perl
requires 'Moo';
```

Define real local classes in `t/typed_view.t`:

```perl
{
    package Local::View::HTML::Contacts::Index;
    use Moo;
    has title => (is => 'ro', required => 1);
    has contacts => (is => 'ro', required => 1);
}

{
    package Local::View::Explicit;
    use Moo;
    has title => (is => 'ro', required => 1);
    sub template { 'components/navigation' }
}
```

Render the first through `render_view` with `view_namespace => 'Local::View'` and assert `html/contacts/index.epl` sees `$self->title`. Render the explicit class and assert its method bypasses convention. Assert legacy `$compiled->render($blessed_object)` leaves `$self` undefined and keeps the object in `$_[0]`.

- [ ] **Step 2: Run the test to verify `render_view` is missing**

Run: `prove -lv t/typed_view.t`

Expected: FAIL with `Can't locate object method "render_view"`.

- [ ] **Step 3: Implement the public typed root path**

```perl
sub render_view {
    my ($self, $view) = @_;
    die "render_view requires a blessed view object\n" unless Scalar::Util::blessed($view);
    my $context = $self->_new_render_context(view => $view, root_view => $view);
    return $context->render_view_object($view);
}
```

`render_view_object` resolves an identifier with `_template_for_view`, clones the context with the supplied view, and calls `render_file($kind, $identifier)`, where `$kind` is `root` when the frame stack is empty and `view` otherwise. Do not place the view in legacy `@_`.

- [ ] **Step 4: Pass typed view to object stringification only**

Update `to_safe_string` helper selection:

```perl
my $context = Template::EmbeddedPerl->_current_render_context('to_safe_string');
my $receiver = $context->view || $engine;
return map {
    Scalar::Util::blessed($_) && $_->can('to_safe_string')
        ? $_->to_safe_string($receiver)
        : $_
} @args;
```

Extend `t/stringification.t` with one `render_view` assertion receiving the view and one legacy assertion still receiving the engine.

- [ ] **Step 5: Run typed, lookup, and stringification tests**

Run: `prove -lv t/typed_view.t t/template_lookup.t t/stringification.t`

Expected: PASS; required Moo constructor failures occur before rendering.

- [ ] **Step 6: Run the full suite**

Run: `prove -lr t`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add cpanfile lib/Template/EmbeddedPerl.pm lib/Template/EmbeddedPerl/RenderContext.pm lib/Template/EmbeddedPerl/Compiled.pm t/typed_view.t t/stringification.t t/templates/views
git commit -m "Add typed root view rendering"
```

---

### Task 9: Render Typed Child and Wrapper Views

**Files:**
- Modify: `lib/Template/EmbeddedPerl.pm:208-228`
- Modify: `lib/Template/EmbeddedPerl/RenderContext.pm`
- Modify: `lib/Template/EmbeddedPerl/RenderFrame.pm`
- Extend: `t/typed_view.t`
- Create: `t/templates/views/html/page.epl`
- Create: `t/templates/views/html/navbar.epl`
- Create: `t/templates/views/html/contacts/item.epl`

**Interfaces:**
- Produces: `view($object, [$body])` and `view($logical_name, @constructor_args, [$body]) -> SafeString`.
- Consumes resolver methods `build_view($logical_name, \%args, $context)` and `template_for($view, $context)`.
- Guarantees: resolver context exposes caller through `view` and top-level object through `root_view`.
- Guarantees: wrapper callback receives child object; caller lexical `$self` remains unchanged; wrapper template gets child `$self`.

- [ ] **Step 1: Extend Moo tests with leaf and wrapper classes**

Define `Local::View::HTML::Page`, `Navbar`, and `Contacts::Item` with required constructor attributes, including `root` and `parent` on nested classes. Define a resolver:

```perl
sub build_view {
    my ($self, $name, $args, $context) = @_;
    my $class = "Local::View::$name";
    return $class->new(
        %$args,
        root => $context->root_view,
        parent => $context->view,
    );
}

sub template_for { return }
```

Root fixture:

```epl
%= view 'HTML::Page', title => $self->title, sub ($page) {
  <h1><%= $page->title %></h1>
  <p>root=<%= $self->title %></p>
  %= view 'HTML::Contacts::Item', contact => $self->contacts->[0]
% }
```

Construct the test engine with `preamble => 'use v5.40;'` so callback signatures are explicitly enabled rather than becoming an implicit distribution-wide Perl version requirement.

Page fixture uses `$self->title`, `$self->root`, `$self->parent`, renders a navbar, and yields the body. Assert:

- `$page` is the page object in the callback.
- callback `$self` remains the contacts root.
- page template `$self` is the page.
- item and navbar receive correct `root` and `parent`.
- a preconstructed item object bypasses `build_view`.
- a preconstructed object plus constructor args throws a clear error.
- three nested wrappers render successfully.

- [ ] **Step 2: Run the typed test to verify `view` is unavailable**

Run: `prove -lv t/typed_view.t`

Expected: FAIL compiling templates that call `view`.

- [ ] **Step 3: Implement logical and object child resolution**

```perl
sub build_child_view {
    my ($self, $target, $args) = @_;
    return $target if Scalar::Util::blessed($target) && !@$args;
    die "Preconstructed view objects do not accept constructor arguments\n"
        if Scalar::Util::blessed($target);
    my $resolver = $self->engine->{view_resolver};
    die "Logical view '$target' requires a resolver with build_view\n"
        unless $resolver && $resolver->can('build_view');
    my %args = @$args;
    my $view = $resolver->build_view($target, \%args, $self);
    die "Resolver did not return a blessed view for '$target'\n"
        unless Scalar::Util::blessed($view);
    return $view;
}
```

Reject odd constructor lists before calling the resolver. Treat the final code reference as the optional body callback.

- [ ] **Step 4: Register the `view` helper and scope wrapper bodies**

```perl
view => sub {
    my ($engine, $target, @args) = @_;
    my $body = @args && ref($args[-1]) eq 'CODE' ? pop @args : undef;
    my $context = Template::EmbeddedPerl->_current_render_context('view');
    my $child = $context->build_child_view($target, \@args);
    my $captured = $body ? $body->($child) : '';
    my $output = $context->frame->with_body($captured, sub {
        $context->with(view => $child)->render_view_object($child);
    });
    return $engine->raw($output);
},
```

Do not change Perl lexical scope around the callback; that naturally preserves caller `$self` while the callback argument exposes the wrapper.

- [ ] **Step 5: Run typed, layout, and content tests**

Run: `prove -lv t/typed_view.t t/layout.t t/content_blocks.t`

Expected: PASS for leaf and arbitrarily nested wrapper views.

- [ ] **Step 6: Run the full suite**

Run: `prove -lr t`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/Template/EmbeddedPerl.pm lib/Template/EmbeddedPerl/RenderContext.pm lib/Template/EmbeddedPerl/RenderFrame.pm t/typed_view.t t/templates/views
git commit -m "Add typed child and wrapper views"
```

---

### Task 10: Harden Composition Errors, Cycles, and Cleanup

**Files:**
- Modify: `lib/Template/EmbeddedPerl/Compiled.pm`
- Modify: `lib/Template/EmbeddedPerl/RenderContext.pm`
- Modify: `lib/Template/EmbeddedPerl/RenderFrame.pm`
- Modify: `lib/Template/EmbeddedPerl/Utils.pm`
- Create: `t/composition_errors.t`
- Extend: `t/regressions.t`

**Interfaces:**
- Produces: cycle rejection using active `{kind, identifier}` entries.
- Produces: one `Render stack:` section containing kind, logical identifier/view class, and source.
- Produces: exception-safe restoration of active context, render scopes, default body, and named content lifetime.

- [ ] **Step 1: Write failing error and cleanup tests**

Create temporary fixtures for:

- `partials/self.epl` calling itself.
- `layouts/self.epl` selecting itself.
- `views/html/self.epl` rendering the same active typed view.
- root -> partial -> view where the view dies on line 2.

Assert cycle messages include the repeated identifier and ordered stack. Assert the nested runtime error includes its original message, exact failing source/line, and one render stack showing root, partial, and view. After each failure, render a known-good template with the same engine and assert no old body, named content, stack entry, or helper context remains.

Add two sequential successful top-level renders where the first contributes `content_for css`; assert the second sees no CSS.

- [ ] **Step 2: Run the test to observe recursion or incomplete diagnostics**

Run: `prove -lv t/composition_errors.t`

Expected: FAIL through uncontrolled recursion or missing stack/cleanup assertions.

- [ ] **Step 3: Add cycle checks and guaranteed scope cleanup**

Before `push_render`, compare the new kind/identifier to active entries and die with a chain such as `partial contacts/item -> partial contacts/item`. Use eval with cleanup in this order:

```perl
my ($output, $error);
$frame->push_render(%entry);
{
    local $Template::EmbeddedPerl::ACTIVE_RENDERER = $context;
    eval { $output = $code->($context, @args); 1 } or $error = $@;
}
my $stack = [map {+{ %$_ }} @{$frame->render_stack}];
$frame->pop_render;
die decorate_render_error($error, $stack) if $error;
return $output;
```

Keep layout application inside the eval and before `pop_render`. Keep default bodies localized with `local`. Never store frame state on the engine or compiled cache.

- [ ] **Step 4: Format a render stack exactly once**

Add `decorate_render_error($error, $stack)` to `Utils.pm`. Return the original error unchanged if it already contains a terminal `Render stack:` marker; otherwise append lines formatted as:

```text
Render stack:
  root contacts/index (/path/contacts/index.epl)
  partial contacts/item (/path/contacts/item.epl)
  view Local::View::HTML::ContactCard (/path/html/contact_card.epl)
```

Preserve `generate_error_message` output before appending the stack.

- [ ] **Step 5: Run all composition and regression tests**

Run: `prove -lv t/composition_errors.t t/regressions.t t/render_context.t t/partial.t t/layout.t t/content_blocks.t t/typed_view.t`

Expected: PASS with no duplicate stack sections.

- [ ] **Step 6: Run the full suite**

Run: `prove -lr t`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/Template/EmbeddedPerl/Compiled.pm lib/Template/EmbeddedPerl/RenderContext.pm lib/Template/EmbeddedPerl/RenderFrame.pm lib/Template/EmbeddedPerl/Utils.pm t/composition_errors.t t/regressions.t
git commit -m "Harden nested rendering diagnostics and cleanup"
```

---

### Task 11: Document the Public API and Cookbook

**Files:**
- Modify: `lib/Template/EmbeddedPerl.pm` POD after `TEMPLATE SYNTAX`, constructor options, and methods
- Modify: `README.mkdn`
- Modify: `Changes`
- Create: `docs/cookbook/typed-views.md`
- Create: `t/documentation.t`

**Interfaces:**
- Documents: `smart_lines`, `args`, `partial`, `layout`, `yield`, `content_for`, `content_replace`, `has_content`, `render_view`, `view_namespace`, resolver protocol, and ordered `directories`.
- Documents: complete untyped and Moo typed examples matching executable tests.

- [ ] **Step 1: Write an executable documentation smoke test**

`t/documentation.t` first asserts that `docs/cookbook/typed-views.md` exists, then constructs the same untyped page and typed Moo page using temporary template directories. Assert both render complete HTML, lazy defaults work, a partial is escaped once, the typed page is found by snake-case convention, and a typed wrapper yields its body.

Use `do` or ordinary Perl setup in the test rather than parsing Markdown; keep the test code adjacent to matching cookbook snippets so changes are reviewed together.

- [ ] **Step 2: Run the documentation test before writing examples**

Run: `prove -lv t/documentation.t`

Expected: FAIL because `docs/cookbook/typed-views.md` does not exist yet; the executable rendering assertions already pass against Tasks 1-10.

- [ ] **Step 3: Write the untyped cookbook section**

Show this progression with exact runnable configuration:

```perl
my $templates = Template::EmbeddedPerl->new(
    directories => ['/srv/app/templates', '/srv/shared/templates'],
    auto_escape => 1,
    smart_lines => 1,
);
```

Include `% args` required/default/lazy forms, a partial with its own arguments, a layout with independent arguments, default yield, and named CSS contributions.

- [ ] **Step 4: Write the Moo typed-view cookbook section**

Define a root Moo class, page wrapper, navbar, and item; show application construction and `$engine->render_view($root)`. Include the resolver's exact `build_view`/`template_for` methods, `root`/`parent`, preconstructed and logical children, wrapper callback scoping, and the mapping:

```text
MyApp::View::HTML::ContactList -> html/contact_list.epl
```

State that Moo is illustrative, any blessed object works, and core never constructs or introspects Moo objects.

- [ ] **Step 5: Update POD, README, and Changes**

Add constructor option and method references with signatures. Add an unreleased section to `Changes` without changing `$VERSION`:

```text
{{$NEXT}}
          - Add smart lines and declarative named template arguments.
          - Add partials, layouts, default/named content blocks, and typed views.
          - Add ordered view-template resolution and nested render diagnostics.
```

Keep `README.mkdn` examples synchronized with POD/cookbook terminology.

- [ ] **Step 6: Run documentation and POD tests**

Run: `prove -lv t/documentation.t`

Expected: PASS.

Run: `perl -Ilib -MTemplate::EmbeddedPerl -e 'print $Template::EmbeddedPerl::VERSION, qq(\n)'`

Expected: `0.001015`; no release version bump occurs in this feature branch.

- [ ] **Step 7: Run final verification**

Run: `prove -lr t`

Expected: every test file and assertion passes.

Run: `git diff --check`

Expected: no output and exit status 0.

- [ ] **Step 8: Commit**

```bash
git add Changes README.mkdn cpanfile docs/cookbook/typed-views.md lib/Template/EmbeddedPerl.pm t/documentation.t
git commit -m "Document template composition and typed views"
```

---

## Final Review Gate

- [ ] Confirm every existing test still passes without `smart_lines` enabled.
- [ ] Confirm a legacy blessed first argument remains in `$_[0]` and never becomes `$self`.
- [ ] Confirm every top-level render creates a distinct frame.
- [ ] Confirm partials, layouts, explicit templates, convention views, and resolver views all use ordered `directories` lookup.
- [ ] Confirm package conversion covers `HTML`, `HTMLPage`, and `ContactList` exactly.
- [ ] Confirm args defaults distinguish absent keys from explicit `undef` and lazy factories run at most once.
- [ ] Confirm named content appends in render order and does not leak to a later render.
- [ ] Confirm typed root and nested objects use the same template precedence.
- [ ] Confirm wrapper body `$self` is the caller, wrapper template `$self` is the wrapper, and the callback receives the wrapper argument.
- [ ] Confirm custom helpers still receive the engine and typed `to_safe_string` receives the active view.
- [ ] Confirm nested failures contain one source-aware render stack and leave the engine reusable.
- [ ] Invoke `superpowers:requesting-code-review` before integration after all tasks pass.
