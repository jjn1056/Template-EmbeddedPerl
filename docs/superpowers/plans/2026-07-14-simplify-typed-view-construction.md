# Simplified Typed View Construction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unreleased resolver protocol with convention-based logical view construction and one optional `view_factory` callback, while preserving object template overrides, Moo support, nested wrappers, helpers, and diagnostics.

**Architecture:** Keep template selection on `Template::EmbeddedPerl` and request-local composition on `Template::EmbeddedPerl::RenderContext`. Move logical-name validation, namespace expansion, class loading, default `new`, and optional factory invocation into one engine method called by `RenderContext->build_child_view`; reduce object-to-template selection to `$view->template` followed by the existing namespace convention.

**Tech Stack:** Perl 5.40, Template::EmbeddedPerl, Moo in tests/examples only, Test::Most, `prove`, POD.

## Global Constraints

- Do not add Moo or another object system as a runtime dependency.
- Default logical construction passes only arguments explicitly supplied to `view`.
- `view_factory` has the exact signature `sub ($class, $args_hashref, $context)` and changes construction only.
- Preconstructed objects passed to `render_view` or `view` bypass `view_factory`.
- Template selection is exactly: a nonempty `$view->template`, then the `view_namespace` convention, then a source-aware error.
- Do not retain `view_resolver`, `build_view`, or `template_for` compatibility behavior.
- Package suffixes remain independently converted from TitleCase/CamelCase to lowercase snake case, preserving acronym runs.
- All template identifiers continue through the ordered `directories` search path.
- Existing untyped rendering, `args`, helpers, partials, layouts, blocks, escaping, and smart-line behavior must remain unchanged.

## File Structure

- Modify `lib/Template/EmbeddedPerl.pm`: own logical class expansion/loading/construction, expose `view_factory` configuration in POD, and remove resolver-based template selection.
- Modify `lib/Template/EmbeddedPerl/RenderContext.pm`: delegate logical child construction to the engine and call context-free object template selection.
- Modify `t/typed_view.t`: exercise default Moo construction, custom factories, wrappers, preconstructed objects, class loading, and construction diagnostics.
- Modify `t/templates/views/components/collision.epl`: use a namespace-relative logical child under the new convention.
- Modify `t/template_lookup.t`: lock template precedence to object override then namespace convention.
- Create `t/lib/Loaded/View/HTML/Notice.pm`: prove that an unloaded logical class is required through Perl's package-file convention.
- Create `t/templates/views/html/greeting.epl` and `t/templates/views/html/notice.epl`: fixtures for default and file-loaded views.
- Modify `t/documentation.t`: executable example of helpers, default construction, and `view_factory` injection.
- Modify `docs/cookbook/typed-views.md`: document the zero-ceremony path first and the factory path second.
- Modify `README.mkdn` and `lib/Template/EmbeddedPerl.pm` POD only where resolver-era wording exists.

---

### Task 1: Replace Resolver Construction With Default `new` And `view_factory`

**Files:**
- Modify: `lib/Template/EmbeddedPerl.pm:200-275,460-510`
- Modify: `lib/Template/EmbeddedPerl/RenderContext.pm:108-145`
- Modify: `t/typed_view.t`
- Modify: `t/templates/views/components/collision.epl`
- Create: `t/lib/Loaded/View/HTML/Notice.pm`
- Create: `t/templates/views/html/greeting.epl`
- Create: `t/templates/views/html/notice.epl`

**Interfaces:**
- Consumes: `RenderContext->view`, `RenderContext->root_view`, and `RenderContext->execute_render($entry, $callback)`.
- Produces: `Template::EmbeddedPerl->_logical_view_class($logical_name) -> $expanded_class`.
- Produces: `Template::EmbeddedPerl->_construct_view($logical_name, \%args, $context) -> $blessed_view`.
- Produces: optional constructor configuration `view_factory => sub { my ($class, $args, $context) = @_; ... }`.

- [ ] **Step 1: Add failing default-construction and class-loading fixtures**

Add these local Moo classes near the other packages in `t/typed_view.t`:

```perl
{
    package Local::EasyView::HTML::Greeting;
    use Moo;

    has name => (is => 'ro', required => 1);
    has punctuation => (
        is => 'ro',
        default => sub { '!' },
        coerce => sub { $_[0] eq 'question' ? '?' : $_[0] },
        isa => sub {
            die "punctuation must be one character\n"
                unless defined($_[0]) && !ref($_[0]) && length($_[0]) == 1;
        },
    );
}

{
    package Local::EasyView::GreetingAdapter;
    use Moo;

    has name => (is => 'ro', required => 1);
    sub punctuation { '~' }
    sub template { 'html/greeting' }
}
```

Create `t/templates/views/html/greeting.epl`:

```epl
<p><%= $self->name %><%= $self->punctuation %></p>
```

Create `t/lib/Loaded/View/HTML/Notice.pm`:

```perl
package Loaded::View::HTML::Notice;

use strict;
use warnings;
use Moo;

has message => (is => 'ro', required => 1);

1;
```

Create `t/templates/views/html/notice.epl`:

```epl
<aside><%= $self->message %></aside>
```

Add public rendering tests before the existing complex wrapper tree:

```perl
my $easy_engine = Template::EmbeddedPerl->new(
    directories => [$template_directory],
    view_namespace => 'Local::EasyView',
);

is(
    $easy_engine->from_string(
        q{<%= view 'HTML::Greeting', name => 'Ada' %>},
        source => 'default-construction.epl',
    )->render,
    "<p>Ada!</p>\n",
    'a logical Moo view is constructed with new and its attribute default applies',
);

is(
    $easy_engine->from_string(
        q{<%= view 'HTML::Greeting', name => 'Ada', punctuation => 'question' %>},
        source => 'explicit-construction.epl',
    )->render,
    "<p>Ada?</p>\n",
    'explicit template arguments are passed through Moo coercion',
);

my $loaded_engine = Template::EmbeddedPerl->new(
    directories => [$template_directory],
    view_namespace => 'Loaded::View',
);
{
    local @INC = (File::Spec->catdir(qw(t lib)), @INC);
    is(
        $loaded_engine->from_string(
            q{<%= view 'HTML::Notice', message => 'Loaded' %>},
            source => 'class-loading.epl',
        )->render,
        "<aside>Loaded</aside>\n",
        'a logical view class is required from its package path before construction',
    );
}
```

- [ ] **Step 2: Convert the complex wrapper test from a resolver object to a factory callback**

Delete `Local::View::Resolver`, `Local::View::InvalidResolver`, and `Local::View::CollisionResolver`. Replace `$resolver` and `view_resolver` in the primary engine setup with an array of calls and this callback:

```perl
my @factory_calls;
my $engine = Template::EmbeddedPerl->new(
    directories => [$template_directory],
    view_namespace => 'Local::View',
    view_factory => sub {
        my ($class, $args, $context) = @_;
        my $call = {
            class => $class,
            args => {%$args},
            context => $context,
        };
        push @factory_calls, $call;
        my $view = $class->new(
            %$args,
            root => $context->root_view,
            parent => $context->view,
        );
        $call->{view} = $view;
        return $view;
    },
    auto_escape => 1,
);
```

Update call assertions to use the expanded class and the array:

```perl
my ($page_call) = grep { $_->{class} eq 'Local::View::HTML::Page' } @factory_calls;
my ($item_call) = grep { $_->{class} eq 'Local::View::HTML::Contacts::Item' } @factory_calls;
my ($navbar_call) = grep { $_->{class} eq 'Local::View::HTML::Navbar' } @factory_calls;

is_deeply(
    $page_call->{args},
    {title => 'Contacts'},
    'view_factory receives only explicit constructor arguments',
);
is($page_call->{context}->view, $root, 'factory context exposes the caller view');
is($page_call->{context}->root_view, $root, 'factory context preserves the typed root');
```

Replace every `@{$resolver->build_calls}` count with `scalar @factory_calls`, and keep the existing preconstructed leaf and wrapper assertions so they prove the callback count does not change.

Change the collision fixture to use default construction without a resolver. Make `components/collision.epl` render `CollisionLeaf`:

```epl
<%= view 'CollisionLeaf' %>
```

Construct its engine with `view_namespace => 'Local::View'`; the existing `Local::View::CollisionLeaf` class and explicit template then prove logical render keys do not collide with object identity keys.

- [ ] **Step 3: Add failing construction contract and diagnostic tests**

Replace the obsolete “without resolver” failure with a successful default-construction assertion using `$easy_engine`. Add these cases to `t/typed_view.t`:

```perl
throws_ok {
    $easy_engine->from_string(
        q{<%= view '../Greeting', name => 'Ada' %>},
        source => 'invalid-logical-name.epl',
    )->render;
} qr/Invalid logical view name '\.\.\/Greeting'/,
    'logical names must be relative Perl package names';

my $no_namespace = Template::EmbeddedPerl->new(
    directories => [$template_directory],
);
throws_ok {
    $no_namespace->from_string(
        q{<%= view 'HTML::Greeting', name => 'Ada' %>},
        source => 'missing-view-namespace.epl',
    )->render;
} qr/Logical view 'HTML::Greeting' requires view_namespace/,
    'logical construction requires a configured namespace';

throws_ok {
    $easy_engine->from_string(
        q{<%= view 'HTML::Missing' %>},
        source => 'missing-view-class.epl',
    )->render;
} qr/Failed to load logical view 'HTML::Missing' as 'Local::EasyView::HTML::Missing'/,
    'class-loading errors identify logical and expanded names';

throws_ok {
    $easy_engine->from_string(
        q{<%= view 'HTML::Greeting' %>},
        source => 'moo-constructor-error.epl',
    )->render;
} qr/Failed to construct logical view 'HTML::Greeting'.*Missing required arguments?: name/s,
    'Moo constructor errors retain their original detail';

throws_ok {
    $easy_engine->from_string(
        q{<%= view 'HTML::Greeting', name => 'Ada', punctuation => 'long' %>},
        source => 'moo-type-error.epl',
    )->render;
} qr/Failed to construct logical view 'HTML::Greeting'.*punctuation must be one character/s,
    'Moo isa failures retain their original detail';

my $bad_factory_engine = Template::EmbeddedPerl->new(
    directories => [$template_directory],
    view_namespace => 'Local::EasyView',
    view_factory => sub { return {} },
);
throws_ok {
    $bad_factory_engine->from_string(
        q{<%= view 'HTML::Greeting', name => 'Ada' %>},
        source => 'bad-view-factory.epl',
    )->render;
} qr/view_factory did not return a blessed view for 'HTML::Greeting'/,
    'view_factory must return a blessed object';

my $throwing_factory_engine = Template::EmbeddedPerl->new(
    directories => [$template_directory],
    view_namespace => 'Local::EasyView',
    view_factory => sub { die "container unavailable\n" },
);
throws_ok {
    $throwing_factory_engine->from_string(
        q{<%= view 'HTML::Greeting', name => 'Ada' %>},
        source => 'throwing-view-factory.epl',
    )->render;
} qr/view_factory failed for logical view 'HTML::Greeting'.*container unavailable/s,
    'view_factory errors identify the operation and retain the original exception';

my $invalid_factory_engine = Template::EmbeddedPerl->new(
    directories => [$template_directory],
    view_namespace => 'Local::EasyView',
    view_factory => 'not a callback',
);
throws_ok {
    $invalid_factory_engine->from_string(
        q{<%= view 'HTML::Greeting', name => 'Ada' %>},
        source => 'invalid-view-factory.epl',
    )->render;
} qr/view_factory must be a code reference/,
    'view_factory configuration is validated when logical construction uses it';

my $adapter_factory_engine = Template::EmbeddedPerl->new(
    directories => [$template_directory],
    view_namespace => 'Local::EasyView',
    view_factory => sub {
        my ($class, $args, $context) = @_;
        is($class, 'Local::EasyView::HTML::Greeting', 'factory receives the requested class');
        return Local::EasyView::GreetingAdapter->new(%$args);
    },
);
is(
    $adapter_factory_engine->from_string(
        q{<%= view 'HTML::Greeting', name => 'Ada' %>},
        source => 'adapter-view-factory.epl',
    )->render,
    "<p>Ada~</p>\n",
    'view_factory may return a different blessed class with its own template policy',
);
```

For the bad factory and Moo failure, retain assertions matching the two-entry render stack: the root source followed by `view HTML::Greeting (unknown)`.

- [ ] **Step 4: Run the typed-view test to verify the new contract fails**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/typed_view.t
```

Expected: FAIL because logical views still require `view_resolver->build_view`, and `view_factory` is not called.

- [ ] **Step 5: Implement class expansion and construction on the engine**

Add these methods beside `_class_to_template` in `lib/Template/EmbeddedPerl.pm`:

```perl
sub _logical_view_class {
  my ($self, $logical_name) = @_;

  die "Invalid logical view name '$logical_name'\n"
    unless defined($logical_name)
      && !ref($logical_name)
      && $logical_name =~ /\A[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*\z/;

  my $namespace = $self->{view_namespace};
  die "Logical view '$logical_name' requires view_namespace\n"
    unless defined($namespace) && length($namespace);
  die "Invalid view_namespace '$namespace'\n"
    unless $namespace =~ /\A[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*\z/;

  return "$namespace\::$logical_name";
}

sub _construct_view {
  my ($self, $logical_name, $args, $context) = @_;
  my $class = $self->_logical_view_class($logical_name);

  unless ($class->can('new')) {
    my $class_file = "$class.pm";
    $class_file =~ s{::}{/}g;
    my $loaded = eval { require $class_file; 1 };
    die "Failed to load logical view '$logical_name' as '$class': $@"
      unless $loaded;
  }

  my $factory = $self->{view_factory};
  die "view_factory must be a code reference\n"
    if defined($factory) && ref($factory) ne 'CODE';

  my $view;
  if ($factory) {
    my $constructed = eval {
      $view = $factory->($class, {%$args}, $context);
      1;
    };
    die "view_factory failed for logical view '$logical_name' as '$class': $@"
      unless $constructed;
  } else {
    my $constructed = eval {
      $view = $class->new(%$args);
      1;
    };
    die "Failed to construct logical view '$logical_name' as '$class': $@"
      unless $constructed;
  }

  die "view_factory did not return a blessed view for '$logical_name'\n"
    if $factory && !Scalar::Util::blessed($view);
  die "Constructor did not return a blessed view for '$logical_name'\n"
    unless Scalar::Util::blessed($view);

  return $view;
}
```

The copied hash reference prevents a factory from mutating the caller's argument container. The returned object may be a subclass or adapter; only blessedness is required.

- [ ] **Step 6: Delegate `RenderContext->build_child_view` to the engine**

Keep the existing preconstructed-object, target-type, and odd-list validation in `lib/Template/EmbeddedPerl/RenderContext.pm`. Replace resolver lookup and invocation inside `execute_render` with:

```perl
            my %constructor_args = @$args;
            return $self->engine->_construct_view(
                $target,
                \%constructor_args,
                $self,
            );
```

Do not add `root`, `parent`, or context to `%constructor_args`; only a configured factory may choose to inject them.

- [ ] **Step 7: Run focused typed-view and context tests**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/typed_view.t t/render_context.t
```

Expected: PASS. The output should include successful assertions for default Moo construction, file-based class loading, factory context, preconstructed bypass, and decorated failures.

- [ ] **Step 8: Commit the construction API**

```bash
git add lib/Template/EmbeddedPerl.pm lib/Template/EmbeddedPerl/RenderContext.pm t/typed_view.t t/lib/Loaded/View/HTML/Notice.pm t/templates/views/html/greeting.epl t/templates/views/html/notice.epl t/templates/views/components/collision.epl
git commit -m "feat: simplify typed view construction"
```

---

### Task 2: Remove External Template Resolution

**Files:**
- Modify: `lib/Template/EmbeddedPerl.pm:483-500`
- Modify: `lib/Template/EmbeddedPerl/RenderContext.pm:49-70`
- Modify: `t/template_lookup.t`
- Modify: `t/typed_view.t`

**Interfaces:**
- Consumes: `_class_to_template($class) -> $identifier`.
- Produces: `_template_for_view($view) -> $identifier` with no context parameter and no external policy hook.

- [ ] **Step 1: Rewrite template-precedence tests without a resolver**

Delete `Local::TemplateLookup::Resolver`, `$resolver`, and `view_resolver` from `t/template_lookup.t`. Move the empty-template class beneath the configured namespace:

```perl
{
    package MyApp::View::Empty;

    sub new { bless {}, shift }
    sub template { '' }
}
```

Update the precedence assertions to:

```perl
is(
    $engine->_template_for_view(Local::TemplateLookup::Explicit->new),
    'objects/explicit',
    'a nonempty object template is authoritative',
);
is(
    $engine->_template_for_view(MyApp::View::Empty->new),
    'empty',
    'an empty object template falls back to the namespace convention',
);
is(
    $engine->_template_for_view(MyApp::View::HTML::ContactList->new),
    'html/contact_list',
    'the namespace convention resolves an object without a template override',
);
```

Keep the existing acronym, ordered-directory, fallback-directory, outside-namespace, and complete missing-candidate assertions.

- [ ] **Step 2: Add a failing authoritative-template integration test**

Add this class to `t/typed_view.t`:

```perl
{
    package Local::View::MissingExplicit;
    use Moo;

    sub template { 'missing/explicit' }
}
```

Then assert that rendering does not try a conventional fallback:

```perl
throws_ok {
    $engine->render_view(Local::View::MissingExplicit->new);
} qr/Template 'missing\/explicit' not found; searched:/,
    'a missing explicit template fails without convention fallback';
```

- [ ] **Step 3: Run lookup tests as characterization before deleting the dead branch**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/template_lookup.t t/typed_view.t
```

Expected: PASS. With no resolver configured, current behavior already reaches the
object/convention paths; this run establishes that deleting the now-unreachable
resolver branch does not change those paths.

- [ ] **Step 4: Reduce `_template_for_view` to two deterministic cases**

Replace the method in `lib/Template/EmbeddedPerl.pm` with:

```perl
sub _template_for_view {
  my ($self, $view) = @_;
  my $class = Scalar::Util::blessed($view) || ref($view) || "$view";

  if (Scalar::Util::blessed($view) && $view->can('template')) {
    my $template = $view->template;
    return $template if defined($template) && length($template);
  }

  return $self->_class_to_template($class);
}
```

In `RenderContext->render_view_object`, change:

```perl
my $template_identifier = $self->engine->_template_for_view($view, $self);
```

to:

```perl
my $template_identifier = $self->engine->_template_for_view($view);
```

- [ ] **Step 5: Run focused template and typed-view tests**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/template_lookup.t t/typed_view.t t/composition_errors.t
```

Expected: PASS. Explicit overrides, convention mapping, virtual loading, ordered lookup, and missing-template render stacks must remain green.

- [ ] **Step 6: Commit deterministic template selection**

```bash
git add lib/Template/EmbeddedPerl.pm lib/Template/EmbeddedPerl/RenderContext.pm t/template_lookup.t t/typed_view.t
git commit -m "refactor: remove typed view template resolver"
```

---

### Task 3: Update Executable Documentation And Helper Examples

**Files:**
- Modify: `t/documentation.t`
- Modify: `docs/cookbook/typed-views.md`
- Modify: `lib/Template/EmbeddedPerl.pm:1050-1110,1394-1425`
- Modify: `README.mkdn` if the obsolete names occur there

**Interfaces:**
- Consumes: public `view_namespace`, `view_factory`, `render_view`, `view`, `helpers`, `RenderContext->view`, and `RenderContext->root_view`.
- Produces: executable documentation of the zero-factory Moo path and dependency-injected wrapper path.

- [ ] **Step 1: Run the resolver-era executable example to verify it fails**

Run after Tasks 1 and 2:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/documentation.t
```

Expected: FAIL with a Moo missing `root`/`parent` constructor error because the
obsolete `view_resolver` option is no longer consulted.

- [ ] **Step 2: Convert the documentation integration test to `view_factory`**

Delete `Documentation::View::Resolver`. Give `Documentation::View::HTML::ContactItem` the sole explicit item-template policy:

```perl
sub template { 'components/contact_item' }
```

Replace `$resolver` with a call log and configure the typed engine as follows:

```perl
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
```

Use the helper from the typed item fixture:

```epl
<li class="contact" data-source="object"><%= typed_label $self->label %> root=<%= $self->root ? $self->root->title : 'none' %> parent=<%= $self->parent ? $self->parent->title : 'none' %></li>
```

Add these compact Moo classes to `t/documentation.t` for exhaustive helper-scope
coverage:

```perl
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
```

Create exact single-line templates so the expected output is stable:

```perl
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
```

After constructing `$typed_engine`, render the matrix and assert every scope:

```perl
is(
    $typed_engine->render_view(
        Documentation::View::HTML::HelperMatrix->new(title => 'Root'),
    ),
    '<layout>LAYOUT:ROOT|<root>ROOT:ROOT|<partial>PARTIAL:ROOT</partial>|'
        . '<wrapper>WRAPPER:WRAPPED|BODY:ROOT</wrapper></root></layout>',
    'helpers work with typed self in roots, partials, layouts, wrapper bodies, and wrapper templates',
);
```

The existing logical contact-item template uses `typed_label`, which separately
proves helper availability in an ordinary nested leaf view.

Update expected output and assertions to use `class` instead of `logical_name`:

```perl
my ($root_navbar) = grep {
    $_->{class} eq 'Documentation::View::HTML::Navbar'
        && $_->{view}->active eq 'contacts'
} @factory_calls;
my ($wrapper) = grep {
    $_->{class} eq 'Documentation::View::HTMLPage::Shell'
} @factory_calls;
```

Retain the prebuilt item in the test and assert the factory did not construct it. This executable example must continue proving wrapper callback scoping, `root`, `parent`, escaping, and ordered directories.

- [ ] **Step 3: Run the documentation test before editing prose**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/documentation.t
```

Expected: PASS after the executable example is updated. It must include assertions for the typed helper and preconstructed-object factory bypass.

- [ ] **Step 4: Rewrite the cookbook with the simple path first**

In `docs/cookbook/typed-views.md`, replace statements that the engine never constructs objects with this contract:

```markdown
For a logical call such as `view 'HTML::Navbar', active => 'contacts'`, the
engine prefixes `view_namespace`, loads `MyApp::View::HTML::Navbar`, and calls
`->new(active => 'contacts')`. Moo remains optional; the engine only relies on
an ordinary constructor returning a blessed object.
```

Show the zero-factory engine before dependency injection:

```perl
my $engine = Template::EmbeddedPerl->new(
    directories => ['/srv/app/templates', '/srv/shared/templates'],
    auto_escape => 1,
    smart_lines => 1,
    preamble => 'use v5.40;',
    view_namespace => 'MyApp::View',
    helpers => {
        path_for => sub {
            my ($engine, $route, @args) = @_;
            return $router->path_for($route, @args);
        },
    },
);
```

Then show the optional factory exactly once:

```perl
view_factory => sub {
    my ($class, $args, $context) = @_;
    return $class->new(
        %$args,
        root => $context->root_view,
        parent => $context->view,
    );
},
```

State explicitly that `$args` contains only values supplied by the template, `$context->view` is the current parent, `$context->root_view` is the original typed root, and preconstructed objects bypass the callback. Remove all `template_for` examples; use a view's `template` method for every explicit override.

- [ ] **Step 5: Update module POD configuration and `render_view` documentation**

In `lib/Template/EmbeddedPerl.pm` POD:

1. Remove resolver-supplied templates from the `directories` description.
2. Describe `view_namespace` as both the logical class prefix and convention template prefix.
3. Replace `view_resolver` with `view_factory` and its exact callback signature.
4. Reduce `render_view` precedence to object `template` then namespace convention.
5. Explain default `$class->new(%args)`, factory-only injection, and preconstructed bypass.
6. Keep Moo explicitly test/example-only.

Use this configuration excerpt:

```perl
my $templates = Template::EmbeddedPerl->new(
    view_namespace => 'MyApp::View',
    view_factory => sub {
        my ($class, $args, $context) = @_;
        return $class->new(%$args);
    },
);
```

- [ ] **Step 6: Verify prose and executable documentation**

Run:

```bash
rg -n "view_resolver|template_for|build_view|resolver-supplied" lib t docs/cookbook README.mkdn
```

Expected: no matches.

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/documentation.t
perlbrew exec --with perl-5.40.0@default podchecker lib/Template/EmbeddedPerl.pm
```

Expected: the test passes and POD syntax is reported as OK.

- [ ] **Step 7: Commit documentation and executable examples**

```bash
git add t/documentation.t docs/cookbook/typed-views.md lib/Template/EmbeddedPerl.pm README.mkdn
git commit -m "docs: explain convention-based typed views"
```

If `README.mkdn` contains no resolver-era wording and is unchanged, omit it from `git add`.

---

### Task 4: Verify Compatibility And Remove Obsolete API Traces

**Files:**
- Modify only files identified by the obsolete-reference scan
- Test: all files under `t/`

**Interfaces:**
- Consumes: the completed construction and template-selection APIs from Tasks 1-3.
- Produces: a clean tree with no executable or public-documentation references to the resolver protocol and a passing full test suite.

- [ ] **Step 1: Scan executable code and public documentation for obsolete API names**

Run:

```bash
rg -n "view_resolver|template_for|build_view" lib t docs/cookbook README.mkdn
```

Expected: no matches. The historical design and implementation plan may retain the terms because they record the superseded design; production code, tests, cookbook, and public POD may not.

- [ ] **Step 2: Run focused behavior suites**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/typed_view.t t/template_lookup.t t/documentation.t t/composition_errors.t t/stringification.t
```

Expected: PASS. Confirm the assertion output covers default Moo construction, factory argument/context values, preconstructed bypass, explicit-template authority, directory priority, helper availability, and source-aware errors.

- [ ] **Step 3: Run the complete suite**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lr t
```

Expected: PASS with every test file successful and no unexpected warnings.

- [ ] **Step 4: Check patch hygiene**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` prints nothing. `git status --short` lists only intentional files from this plan, or is clean if every task commit already captured them.

- [ ] **Step 5: Commit any final verification corrections**

If the preceding checks required changes, stage only those files and commit them:

```bash
git add lib t docs/cookbook README.mkdn
git commit -m "test: complete typed view factory coverage"
```

If no files changed, do not create an empty commit.
