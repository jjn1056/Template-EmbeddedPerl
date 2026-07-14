# POD Cookbook And Contacts Tutorial Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an installed POD tutorial and cookbook backed by runnable, tested untyped and typed Contacts applications.

**Architecture:** Keep `Template::EmbeddedPerl` as the unchanged engine and add documentation around two framework-neutral example applications. The untyped application is the beginner tutorial endpoint; the typed application refactors the same behavior through Moo views, convention lookup, a wrapper view, and `view_factory`. Tests execute the real example files, verify byte-for-byte parity, inspect required POD structure, and validate the built distribution.

**Tech Stack:** Perl 5.40 test environment, Template::EmbeddedPerl, Moo for the typed example only, Test::Most, POD, Pod::Checker, Dist::Zilla.

## Global Constraints

- Audience priority is: new Template::EmbeddedPerl users, existing users seeking recipes, then framework authors.
- Documentation must be installed POD under `lib/`, discoverable with `perldoc`.
- The tutorial uses one evolving, framework-neutral Contacts application with in-memory data.
- Complete untyped and typed endpoint applications are checked in under `examples/contacts/`.
- The typed application refactors the same Contacts behavior and uses Moo only for concise examples; Moo is not a Template::EmbeddedPerl runtime dependency.
- The untyped and typed applications produce byte-for-byte equivalent HTML for their shared fixture data.
- Typed-view support remains explicitly experimental with this exact notice: `B<Experimental:> Typed view support, including C<render_view>, C<view>, C<view_namespace>, and C<view_factory>, may change as real-world integration needs become clearer.`
- Do not change template engine behavior, public APIs, escaping semantics, or compiler code.
- Do not add a web framework, database, router, server, or network dependency.
- The old Markdown typed-view cookbook is removed after all unique content is migrated.
- The internal `docs/` tree remains excluded from built distributions; installed POD and `examples/contacts/` must be included.
- Preserve the existing working-tree `dist.ini` change adding `match = ^docs/`; it belongs in the final integration commit and must not be reverted.
- Use ASCII for all new files.
- Every complete example labeled runnable must execute; partial examples must be labeled as fragments.
- Run Perl commands through `perlbrew exec --with perl-5.40.0@default`.

---

## File Map

### New installed documentation

- `lib/Template/EmbeddedPerl/Tutorial.pod`: newcomer-first progressive Contacts tutorial.
- `lib/Template/EmbeddedPerl/Cookbook.pod`: recipe index and independent task-oriented recipes.
- `lib/Template/EmbeddedPerl/Cookbook/TypedViews.pod`: advanced typed-view refactor of the same application.

### New runnable examples

- `examples/contacts/untyped/app.pl`: command-line entry point for the untyped example.
- `examples/contacts/untyped/lib/Contacts/Untyped/App.pm`: untyped application construction, fixture data, helper, and render API.
- `examples/contacts/untyped/templates/pages/contacts.epl`: untyped root page.
- `examples/contacts/untyped/templates/contacts/item.epl`: untyped contact partial.
- `examples/contacts/untyped/templates/layouts/application.epl`: untyped application layout.
- `examples/contacts/typed/app.pl`: command-line entry point for the typed example.
- `examples/contacts/typed/lib/Contacts/Typed/App.pm`: typed engine, factory, fixture data, and render API.
- `examples/contacts/typed/lib/Contacts/Typed/View/HTML/ContactList.pm`: typed root view.
- `examples/contacts/typed/lib/Contacts/Typed/View/HTML/Page.pm`: typed wrapper view.
- `examples/contacts/typed/lib/Contacts/Typed/View/HTML/ContactItem.pm`: typed child view with explicit template override.
- `examples/contacts/typed/lib/Contacts/Typed/View/HTML/Badge.pm`: preconstructed typed child that bypasses `view_factory`.
- `examples/contacts/typed/templates/html/contact_list.epl`: convention-resolved root template.
- `examples/contacts/typed/templates/html/page.epl`: convention-resolved wrapper template.
- `examples/contacts/typed/templates/contacts/item.epl`: explicitly resolved contact-item template.
- `examples/contacts/typed/templates/contacts/badge.epl`: explicitly resolved preconstructed badge template.
- `examples/contacts/typed/templates/layouts/application.epl`: untyped layout reused by typed rendering.

### Tests and migration

- `t/cookbook_examples.t`: executable examples, parity, required POD structure, and referenced paths.
- `t/documentation.t`: migrate experimental-notice assertions from Markdown to installed POD.
- `README.mkdn`: add perldoc learning path and remove links to pruned Markdown cookbook.
- `dist.ini`: retain the ordered `PruneFiles` rule excluding `docs/`.
- Delete `docs/cookbook/typed-views.md` after migration.

---

### Task 1: Add The Runnable Untyped Contacts Application

**Files:**
- Create: `t/cookbook_examples.t`
- Create: `examples/contacts/untyped/app.pl`
- Create: `examples/contacts/untyped/lib/Contacts/Untyped/App.pm`
- Create: `examples/contacts/untyped/templates/pages/contacts.epl`
- Create: `examples/contacts/untyped/templates/contacts/item.epl`
- Create: `examples/contacts/untyped/templates/layouts/application.epl`

**Interfaces:**
- Produces: `Contacts::Untyped::App->new(%args)`.
- Produces: `$app->render(%named_args) -> Str`.
- Produces: `$app->contacts -> ArrayRef[HashRef]`.
- Produces: `$app->heading_calls -> Int` for demonstrating lazy defaults.
- Produces: a CLI that writes the same HTML as `$app->render` to STDOUT.
- Later tasks use the exact expected HTML constant introduced here as the parity contract.

- [ ] **Step 1: Add a failing executable-example test**

Create `t/cookbook_examples.t` with the following baseline:

```perl
use strict;
use warnings;

use File::Spec;
use Test::Most;
use Template::EmbeddedPerl;

my $root = File::Spec->rel2abs('.');
my $distribution_lib = File::Spec->catdir($root, 'lib');
my $untyped_root = File::Spec->catdir($root, qw(examples contacts untyped));
my $untyped_lib = File::Spec->catdir($untyped_root, 'lib');

unshift @INC, $untyped_lib;
require Contacts::Untyped::App;

my $expected_html = <<'HTML';
<!doctype html>
<html>
<head>
<title>Contacts</title>
<meta name="section" content="contacts">
</head>
<body>
<section class="page">
<main>
<h1>CONTACTS</h1>
<p class="badge">2 contacts</p>
<ul>
<li data-root="Contacts" data-parent="Contacts"><strong>&lt;Ada&gt;</strong> ada@example.test</li>
<li data-root="Contacts" data-parent="Contacts"><strong>Grace</strong> grace@example.test</li>
</ul>
</main>
</section>
</body>
</html>
HTML

sub run_script {
    my ($script) = @_;
    open my $fh, '-|', $^X, "-I$distribution_lib", $script
        or die "Cannot execute $script: $!";
    local $/;
    my $output = <$fh>;
    close $fh or die "Example $script failed";
    return $output;
}

my $untyped = Contacts::Untyped::App->new(root => $untyped_root);
is($untyped->heading_calls, 0, 'lazy heading default has not run before rendering');
is($untyped->render, $expected_html, 'untyped Contacts application renders expected HTML');
is($untyped->heading_calls, 1, 'absent heading evaluates the lazy default once');

$untyped->render(heading => 'Directory');
is($untyped->heading_calls, 1, 'explicit heading bypasses the lazy default');

is(
    run_script(File::Spec->catfile($untyped_root, 'app.pl')),
    $expected_html,
    'untyped command-line example renders expected HTML',
);

done_testing;
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t
```

Expected: FAIL because `Contacts/Untyped/App.pm` does not exist.

- [ ] **Step 3: Implement the untyped application module**

Create `examples/contacts/untyped/lib/Contacts/Untyped/App.pm`:

```perl
package Contacts::Untyped::App;

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;
use Template::EmbeddedPerl;

sub new {
    my ($class, %args) = @_;
    my $root = $args{root} || File::Spec->rel2abs(
        File::Spec->catdir(dirname(__FILE__), qw(.. .. ..)),
    );

    my $self = bless {
        root => $root,
        heading_calls => 0,
    }, $class;

    $self->{engine} = Template::EmbeddedPerl->new(
        directories => [File::Spec->catdir($root, 'templates')],
        smart_lines => 1,
        auto_escape => 1,
        use_cache => 1,
        helpers => {
            display_heading => sub {
                my ($engine, $value) = @_;
                $self->{heading_calls}++;
                return uc $value;
            },
        },
    );

    return $self;
}

sub contacts {
    return [
        {name => '<Ada>', email => 'ada@example.test'},
        {name => 'Grace', email => 'grace@example.test'},
    ];
}

sub heading_calls { $_[0]->{heading_calls} }

sub render {
    my ($self, %args) = @_;
    return $self->{engine}->from_file('pages/contacts')->render(
        contacts => $self->contacts,
        %args,
    );
}

1;
```

- [ ] **Step 4: Add the untyped templates**

Create `examples/contacts/untyped/templates/pages/contacts.epl`:

```epl
% args $contacts, $title = 'Contacts', $heading = sub { display_heading($title) }
% layout 'layouts/application', title => $title
%= content_replace 'head', sub {
<meta name="section" content="contacts">
% }
<section class="page">
<main>
<h1><%= $heading %></h1>
<p class="badge"><%= scalar @$contacts %> contacts</p>
<ul>
% for my $contact (@$contacts) {
%= partial 'contacts/item', contact => $contact, root_title => $title, parent_title => $title
% }
</ul>
</main>
</section>
```

Create `examples/contacts/untyped/templates/contacts/item.epl`:

```epl
% args $contact, $root_title, $parent_title
<li data-root="<%= $root_title %>" data-parent="<%= $parent_title %>"><strong><%= $contact->{name} %></strong> <%= $contact->{email} %></li>
```

Create `examples/contacts/untyped/templates/layouts/application.epl`:

```epl
% args $title
<!doctype html>
<html>
<head>
<title><%= $title %></title>
%= yield 'head'
</head>
<body>
%= yield
</body>
</html>
```

- [ ] **Step 5: Add the untyped CLI**

Create `examples/contacts/untyped/app.pl`:

```perl
#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use Contacts::Untyped::App;

print Contacts::Untyped::App->new(root => $FindBin::Bin)->render;
```

Make the script executable with:

```bash
chmod +x examples/contacts/untyped/app.pl
```

- [ ] **Step 6: Run the focused test GREEN**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t
```

Expected: PASS with 5 tests. If whitespace differs, fix the templates rather
than weakening the exact expected output.

- [ ] **Step 7: Run high-risk existing composition tests**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/args.t t/partial.t t/layout.t t/content_blocks.t t/documentation.t
```

Expected: PASS.

- [ ] **Step 8: Commit Task 1**

```bash
git add t/cookbook_examples.t examples/contacts/untyped
git commit -m "docs: add runnable untyped contacts example"
```

---

### Task 2: Write The Newcomer Tutorial POD

**Files:**
- Create: `lib/Template/EmbeddedPerl/Tutorial.pod`
- Modify: `t/cookbook_examples.t`

**Interfaces:**
- Consumes: `Contacts::Untyped::App`, its example files, and the exact HTML contract from Task 1.
- Produces: installed document `Template::EmbeddedPerl::Tutorial`.
- Produces: a stable set of tutorial headings used by documentation tests and cross-links.

- [ ] **Step 1: Add failing tutorial structure tests**

Before `done_testing` in `t/cookbook_examples.t`, add:

```perl
sub read_file {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh or die "Cannot close $path: $!";
    return $content;
}

my $tutorial_path = File::Spec->catfile(
    $root, qw(lib Template EmbeddedPerl Tutorial.pod),
);
ok(-e $tutorial_path, 'installed tutorial POD exists');

my $tutorial = -e $tutorial_path ? read_file($tutorial_path) : '';
for my $heading (
    'FIRST TEMPLATE',
    'THE CONTACTS APPLICATION',
    'SMART LINES AND NAMED ARGUMENTS',
    'DEFAULTS AND LAZY DEFAULTS',
    'ESCAPING HTML SAFELY',
    'PARTIALS',
    'LAYOUTS',
    'NAMED CONTENT',
    'APPLICATION HELPERS',
    'DIAGNOSING FAILURES',
    'REUSE AND PRODUCTION CONFIGURATION',
    'CHOOSING THE NEXT ABSTRACTION',
) {
    like($tutorial, qr/^=head1 \Q$heading\E$/m, "tutorial contains $heading");
}

like(
    $tutorial,
    qr{examples/contacts/untyped/app\.pl},
    'tutorial points to the runnable untyped application',
);

my $compile_error = eval {
    Template::EmbeddedPerl->from_string(
        "first\n<%= \$missing %>\n",
        source => 'tutorial-compile.epl',
    );
    '';
} || $@;
like(
    $compile_error,
    qr/at tutorial-compile\.epl line 2/,
    'tutorial compile failure reports its template source and line',
);

my $runtime_error = eval {
    Template::EmbeddedPerl->from_string(
        "first\n<% die 'tutorial runtime' %>\n",
        source => 'tutorial-runtime.epl',
    )->render;
    '';
} || $@;
like(
    $runtime_error,
    qr/tutorial runtime at tutorial-runtime\.epl line 2/,
    'tutorial runtime failure reports its template source and line',
);

my @warnings;
{
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    Template::EmbeddedPerl->from_string(
        "first\n<% warn 'tutorial warning' %>\n",
        source => 'tutorial-warning.epl',
    )->render;
}
like(
    join('', @warnings),
    qr/tutorial warning at tutorial-warning\.epl line 2/,
    'tutorial warning reports its template source and line',
);
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t
```

Expected: FAIL because `Tutorial.pod` does not exist and all tutorial headings
are absent.

- [ ] **Step 3: Create the POD shell with exact navigation**

Create `lib/Template/EmbeddedPerl/Tutorial.pod` with this exact top-level
structure:

```pod
=head1 NAME

Template::EmbeddedPerl::Tutorial - Build a Contacts application step by step

=head1 DESCRIPTION

=head1 FIRST TEMPLATE

=head1 THE CONTACTS APPLICATION

=head1 SMART LINES AND NAMED ARGUMENTS

=head1 DEFAULTS AND LAZY DEFAULTS

=head1 ESCAPING HTML SAFELY

=head1 PARTIALS

=head1 LAYOUTS

=head1 NAMED CONTENT

=head1 APPLICATION HELPERS

=head1 DIAGNOSING FAILURES

=head1 REUSE AND PRODUCTION CONFIGURATION

=head1 CHOOSING THE NEXT ABSTRACTION

=head1 SEE ALSO

=cut
```

The DESCRIPTION must tell newcomers to run:

```text
perl examples/contacts/untyped/app.pl
```

It must explain that the example is framework-neutral, uses in-memory data,
and is checked by `t/cookbook_examples.t`.

- [ ] **Step 4: Fill the first five tutorial chapters**

Write complete POD prose and runnable excerpts for:

1. Rendering `Hello, <%= shift %>!` from a string.
2. Constructing the engine with `directories`, `smart_lines`, and
   `auto_escape`.
3. The exact `Contacts::Untyped::App->new` and `render` roles from Task 1.
4. `% args $contacts, $title = 'Contacts', $heading = sub { ... }`.
5. Required, scalar-default, lazy-default, absent, explicit-`undef`, and
   unknown-argument behavior.
6. Escaping `<Ada>` to `&lt;Ada&gt;`, safe composition output, and the trusted
   arbitrary-Perl boundary.

Each chapter must show a visible result before its detailed explanation. Mark
incomplete excerpts with `B<Fragment:>`.

- [ ] **Step 5: Fill the composition chapters**

Use the exact Task 1 files to explain:

- why `contacts/item.epl` is a partial;
- its independent `% args` contract;
- why the page explicitly passes `root_title` and `parent_title`;
- deferred layout registration;
- body `yield` and named `yield 'head'`;
- `content_replace` and the relationship to `content_for` and `has_content`;
- once-only escaping of rendered partial and layout output.

Show the complete final untyped HTML output exactly as asserted in Task 1.

- [ ] **Step 6: Fill helpers, diagnostics, reuse, and abstraction chapters**

Document:

- helper signature `sub { my ($engine, @args) = @_; ... }`;
- the `display_heading` counter as proof that lazy defaults only run when absent;
- one compile error, one runtime error, and one warning with stable source and
  template-line explanations;
- compiled-template reuse and when `use_cache` helps;
- persistent-process expectations;
- `preamble`, ordered directories, and trusted template sources;
- choosing plain templates, partials/layouts, or typed views.

End with:

```pod
=head1 SEE ALSO

L<Template::EmbeddedPerl>, L<Template::EmbeddedPerl::Cookbook>, and
L<Template::EmbeddedPerl::Cookbook::TypedViews>.
```

- [ ] **Step 7: Verify POD and focused tests**

Run:

```bash
perlbrew exec --with perl-5.40.0@default podchecker lib/Template/EmbeddedPerl/Tutorial.pod
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t
```

Expected: POD syntax OK and all tests PASS.

- [ ] **Step 8: Commit Task 2**

```bash
git add lib/Template/EmbeddedPerl/Tutorial.pod t/cookbook_examples.t
git commit -m "docs: add Contacts tutorial POD"
```

---

### Task 3: Write The Task-Oriented Cookbook POD

**Files:**
- Create: `lib/Template/EmbeddedPerl/Cookbook.pod`
- Modify: `t/cookbook_examples.t`

**Interfaces:**
- Consumes: the untyped example and `Template::EmbeddedPerl::Tutorial`.
- Produces: installed document `Template::EmbeddedPerl::Cookbook`.
- Produces: task-oriented cross-links to Tutorial and TypedViews.

- [ ] **Step 1: Add failing cookbook navigation tests**

Before `done_testing` in `t/cookbook_examples.t`, add:

```perl
my $cookbook_path = File::Spec->catfile(
    $root, qw(lib Template EmbeddedPerl Cookbook.pod),
);
ok(-e $cookbook_path, 'installed cookbook POD exists');

my $cookbook = -e $cookbook_path ? read_file($cookbook_path) : '';
for my $heading (
    'WHICH DOCUMENT SHOULD I READ?',
    'RENDERING AND LOADING',
    'TEMPLATE INPUTS',
    'OUTPUT AND ESCAPING',
    'COMPOSITION',
    'SYNTAX AND FORMATTING',
    'HELPERS AND CONFIGURATION',
    'TESTING AND TROUBLESHOOTING',
) {
    like($cookbook, qr/^=head1 \Q$heading\E$/m, "cookbook contains $heading");
}

like(
    $cookbook,
    qr/L<Template::EmbeddedPerl::Tutorial>/,
    'cookbook links newcomers to the tutorial',
);
like(
    $cookbook,
    qr/L<Template::EmbeddedPerl::Cookbook::TypedViews>/,
    'cookbook links framework authors to typed views',
);
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t
```

Expected: FAIL because `Cookbook.pod` does not exist.

- [ ] **Step 3: Create the cookbook navigation and rendering recipes**

Create `lib/Template/EmbeddedPerl/Cookbook.pod` beginning with:

```pod
=head1 NAME

Template::EmbeddedPerl::Cookbook - Recipes for common template tasks

=head1 DESCRIPTION

=head1 WHICH DOCUMENT SHOULD I READ?

=head1 RENDERING AND LOADING
```

The reading guide must direct:

- newcomers to `L<Template::EmbeddedPerl::Tutorial>`;
- recipe readers to the current document;
- framework authors to
  `L<Template::EmbeddedPerl::Cookbook::TypedViews>`.

Add complete recipes for `from_string`, ordered-directory `from_file`,
`from_fh`, `from_data`, compiled-template reuse, and `use_cache`. Every recipe
must have a task-oriented `=head2` title, copyable code, expected result, and a
short explanation of when to use it. Label code as `B<Fragment:>` unless the
block is a complete executable or directly names a checked-in runnable file.

- [ ] **Step 4: Add input, escaping, and composition recipes**

Add these exact `=head1` sections:

```pod
=head1 TEMPLATE INPUTS

=head1 OUTPUT AND ESCAPING

=head1 COMPOSITION
```

Cover all recipes from the approved design:

- required args, scalar defaults, lazy defaults, explicit `undef`, and unknown
  args;
- auto escaping, `raw`, safe strings, URL escaping, JavaScript string escaping,
  and flattening;
- partials, layouts, body yield, named content, and wrapper bodies.

Use the checked-in Contacts paths where a full application context helps. Use
small standalone snippets where the Contacts application would add noise.

- [ ] **Step 5: Add syntax, helper, and troubleshooting recipes**

Add:

```pod
=head1 SYNTAX AND FORMATTING

=head1 HELPERS AND CONFIGURATION

=head1 TESTING AND TROUBLESHOOTING
```

Cover smart lines, expression trim, following-whitespace trim, backslash newline
suppression, escaped markers, custom markers, interpolation, helper addition,
helper override, `preamble`, `prepend`, package-relative directories,
Test::Most usage, exact escaped-output tests, isolated partial/layout tests,
source labels, render stacks, and `DEBUG_TEMPLATE_EMBEDDED_PERL`.

Do not copy the README option inventory. Each `=head2` must answer a concrete
question beginning conceptually with "How do I..." even when the displayed
heading is shorter.

- [ ] **Step 6: Add SEE ALSO and verify POD**

End with:

```pod
=head1 SEE ALSO

L<Template::EmbeddedPerl>, L<Template::EmbeddedPerl::Tutorial>, and
L<Template::EmbeddedPerl::Cookbook::TypedViews>.

=cut
```

Run:

```bash
perlbrew exec --with perl-5.40.0@default podchecker lib/Template/EmbeddedPerl/Cookbook.pod
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t
```

Expected: POD syntax OK and all tests PASS.

- [ ] **Step 7: Commit Task 3**

```bash
git add lib/Template/EmbeddedPerl/Cookbook.pod t/cookbook_examples.t
git commit -m "docs: add task-oriented cookbook POD"
```

---

### Task 4: Add The Runnable Typed Contacts Refactor

**Files:**
- Create: `examples/contacts/typed/app.pl`
- Create: `examples/contacts/typed/lib/Contacts/Typed/App.pm`
- Create: `examples/contacts/typed/lib/Contacts/Typed/View/HTML/ContactList.pm`
- Create: `examples/contacts/typed/lib/Contacts/Typed/View/HTML/Page.pm`
- Create: `examples/contacts/typed/lib/Contacts/Typed/View/HTML/ContactItem.pm`
- Create: `examples/contacts/typed/lib/Contacts/Typed/View/HTML/Badge.pm`
- Create: `examples/contacts/typed/templates/html/contact_list.epl`
- Create: `examples/contacts/typed/templates/html/page.epl`
- Create: `examples/contacts/typed/templates/contacts/item.epl`
- Create: `examples/contacts/typed/templates/contacts/badge.epl`
- Create: `examples/contacts/typed/templates/layouts/application.epl`
- Modify: `t/cookbook_examples.t`

**Interfaces:**
- Consumes: Task 1 exact HTML parity contract.
- Produces: `Contacts::Typed::App->new(%args)`.
- Produces: `$app->render -> Str`.
- Produces: `$app->root_view -> Contacts::Typed::View::HTML::ContactList` after rendering.
- Produces: `$app->factory_calls -> ArrayRef[HashRef]` for root/parent assertions.
- Produces: typed CLI output byte-for-byte equal to the untyped CLI.

- [ ] **Step 1: Add failing typed parity and factory tests**

Before `done_testing` in `t/cookbook_examples.t`, add:

```perl
my $typed_root = File::Spec->catdir($root, qw(examples contacts typed));
my $typed_lib = File::Spec->catdir($typed_root, 'lib');
unshift @INC, $typed_lib;
require Contacts::Typed::App;

my $typed = Contacts::Typed::App->new(root => $typed_root);
my $typed_html = $typed->render;
is($typed_html, $expected_html, 'typed Contacts refactor preserves exact HTML');
is($typed_html, $untyped->render, 'typed and untyped applications have output parity');
is(
    run_script(File::Spec->catfile($typed_root, 'app.pl')),
    $expected_html,
    'typed command-line example renders expected HTML',
);

my $root_view = $typed->root_view;
my ($page_call) = grep {
    $_->{class} eq 'Contacts::Typed::View::HTML::Page'
} @{$typed->factory_calls};
ok($page_call, 'view factory constructs the typed wrapper');
is($page_call->{view}->root, $root_view, 'wrapper receives the typed root');
is($page_call->{view}->parent, $root_view, 'wrapper receives the caller as parent');

my @item_calls = grep {
    $_->{class} eq 'Contacts::Typed::View::HTML::ContactItem'
} @{$typed->factory_calls};
is(scalar @item_calls, 2, 'view factory constructs one typed item per contact');
is($item_calls[0]{view}->root, $root_view, 'typed item receives the root view');
is($item_calls[0]{view}->parent, $root_view, 'wrapper body retains caller parent scope');
ok(
    !(grep { $_->{class} eq 'Contacts::Typed::View::HTML::Badge' } @{$typed->factory_calls}),
    'preconstructed typed child bypasses the view factory',
);
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t
```

Expected: FAIL because `Contacts/Typed/App.pm` does not exist.

- [ ] **Step 3: Create the typed view classes**

Create `ContactList.pm`:

```perl
package Contacts::Typed::View::HTML::ContactList;

use strict;
use warnings;
use Moo;

has title => (is => 'ro', required => 1);
has contacts => (is => 'ro', required => 1);
has prebuilt_badge => (is => 'ro', required => 1);

1;
```

Create `Page.pm`:

```perl
package Contacts::Typed::View::HTML::Page;

use strict;
use warnings;
use Moo;

has title => (is => 'ro', required => 1);
has root => (is => 'ro', required => 1);
has parent => (is => 'ro', required => 1);

1;
```

Create `ContactItem.pm`:

```perl
package Contacts::Typed::View::HTML::ContactItem;

use strict;
use warnings;
use Moo;

has contact => (is => 'ro', required => 1);
has root => (is => 'ro', required => 1);
has parent => (is => 'ro', required => 1);

sub template { 'contacts/item' }

1;
```

Create `Badge.pm`:

```perl
package Contacts::Typed::View::HTML::Badge;

use strict;
use warnings;
use Moo;

has label => (is => 'ro', required => 1);

sub template { 'contacts/badge' }

1;
```

- [ ] **Step 4: Create the typed application module**

Create `examples/contacts/typed/lib/Contacts/Typed/App.pm`:

```perl
package Contacts::Typed::App;

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;
use Template::EmbeddedPerl;
use Contacts::Typed::View::HTML::ContactList;
use Contacts::Typed::View::HTML::Badge;

sub new {
    my ($class, %args) = @_;
    my $root = $args{root} || File::Spec->rel2abs(
        File::Spec->catdir(dirname(__FILE__), qw(.. .. ..)),
    );

    my $self = bless {
        root => $root,
        factory_calls => [],
    }, $class;

    $self->{engine} = Template::EmbeddedPerl->new(
        directories => [File::Spec->catdir($root, 'templates')],
        smart_lines => 1,
        auto_escape => 1,
        use_cache => 1,
        preamble => 'use v5.40;',
        view_namespace => 'Contacts::Typed::View',
        helpers => {
            display_heading => sub {
                my ($engine, $value) = @_;
                return uc $value;
            },
        },
        view_factory => sub {
            my ($class, $values, $context) = @_;
            my $view = $class->new(
                %$values,
                root => $context->root_view,
                parent => $context->view,
            );
            push @{$self->{factory_calls}}, {
                class => $class,
                args => {%$values},
                context => $context,
                view => $view,
            };
            return $view;
        },
    );

    return $self;
}

sub contacts {
    return [
        {name => '<Ada>', email => 'ada@example.test'},
        {name => 'Grace', email => 'grace@example.test'},
    ];
}

sub root_view { $_[0]->{root_view} }
sub factory_calls { $_[0]->{factory_calls} }

sub render {
    my ($self) = @_;
    $self->{factory_calls} = [];
    my $contacts = $self->contacts;
    $self->{root_view} = Contacts::Typed::View::HTML::ContactList->new(
        title => 'Contacts',
        contacts => $contacts,
        prebuilt_badge => Contacts::Typed::View::HTML::Badge->new(
            label => scalar(@$contacts) . ' contacts',
        ),
    );
    return $self->{engine}->render_view($self->{root_view});
}

1;
```

- [ ] **Step 5: Create the typed templates**

Create `templates/html/contact_list.epl`:

```epl
%= view 'HTML::Page', title => $self->title, sub ($page) {
<main>
<h1><%= display_heading $self->title %></h1>
%= view $self->prebuilt_badge
<ul>
% for my $contact (@{$self->contacts}) {
%= view 'HTML::ContactItem', contact => $contact
% }
</ul>
</main>
% }
```

Create `templates/html/page.epl`:

```epl
% layout 'layouts/application', title => $self->title
%= content_replace 'head', sub {
<meta name="section" content="contacts">
% }
<section class="page">
%= yield
</section>
```

Create `templates/contacts/item.epl`:

```epl
<li data-root="<%= $self->root->title %>" data-parent="<%= $self->parent->title %>"><strong><%= $self->contact->{name} %></strong> <%= $self->contact->{email} %></li>
```

Create `templates/contacts/badge.epl`:

```epl
<p class="badge"><%= $self->label %></p>
```

Create `templates/layouts/application.epl` with the exact same contents as the
Task 1 untyped layout. The duplication is intentional: each shipped example
must run independently.

- [ ] **Step 6: Add the typed CLI**

Create `examples/contacts/typed/app.pl`:

```perl
#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use Contacts::Typed::App;

print Contacts::Typed::App->new(root => $FindBin::Bin)->render;
```

Run:

```bash
chmod +x examples/contacts/typed/app.pl
```

- [ ] **Step 7: Run typed parity tests GREEN**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t t/typed_view.t t/composition_errors.t
```

Expected: PASS. If typed output differs, fix the typed templates rather than
loosening parity.

- [ ] **Step 8: Commit Task 4**

```bash
git add examples/contacts/typed t/cookbook_examples.t
git commit -m "docs: add runnable typed contacts example"
```

---

### Task 5: Migrate The Typed-View Cookbook To Installed POD

**Files:**
- Create: `lib/Template/EmbeddedPerl/Cookbook/TypedViews.pod`
- Modify: `t/cookbook_examples.t`
- Modify: `t/documentation.t`
- Delete: `docs/cookbook/typed-views.md`

**Interfaces:**
- Consumes: typed application classes, templates, factory records, and parity tests from Task 4.
- Produces: installed document `Template::EmbeddedPerl::Cookbook::TypedViews`.
- Preserves: exact experimental notice required by Global Constraints.

- [ ] **Step 1: Add failing TypedViews POD and migration tests**

Before `done_testing` in `t/cookbook_examples.t`, add:

```perl
my $typed_views_path = File::Spec->catfile(
    $root, qw(lib Template EmbeddedPerl Cookbook TypedViews.pod),
);
ok(-e $typed_views_path, 'installed typed-view cookbook POD exists');

my $typed_views = -e $typed_views_path ? read_file($typed_views_path) : '';
for my $heading (
    'WHY INTRODUCE A TYPED VIEW?',
    'THE ROOT VIEW',
    'TYPED CHILD VIEWS',
    'WRAPPER VIEWS',
    'INJECTING ROOT AND PARENT',
    'COMPOSING THE VIEW TREE',
    'CHOOSING BETWEEN BOTH DESIGNS',
) {
    like($typed_views, qr/^=head1 \Q$heading\E$/m, "typed-view cookbook contains $heading");
}

like(
    $typed_views,
    qr/B<Experimental:> Typed view support, including C<render_view>, C<view>, C<view_namespace>, and C<view_factory>, may change as real-world integration needs become clearer\./,
    'typed-view POD carries the exact experimental notice',
);
ok(
    !-e File::Spec->catfile($root, qw(docs cookbook typed-views.md)),
    'old Markdown cookbook is removed after migration',
);
```

- [ ] **Step 2: Change the documentation notice test to expect POD**

In `t/documentation.t`, replace the Markdown cookbook path with:

```perl
my $cookbook = File::Spec->catfile(
    qw(lib Template EmbeddedPerl Cookbook TypedViews.pod),
);
ok(-e $cookbook, 'the installed typed-view cookbook is present');
```

Delete the existing two-document `for my $document` Markdown loop. After the
existing `$markdown_notice` and `$pod_notice` declarations, insert these exact
assertions:

```perl
ok(
    markdown_notice_follows_heading(
        'README.mkdn',
        '## render\\_view',
        $markdown_notice,
    ),
    'README marks typed views as experimental',
);

ok(
    pod_notice_follows_heading(
        $cookbook,
        '=head1 DESCRIPTION',
        $pod_notice,
    ),
    'cookbook marks typed views as experimental',
);

ok(
    pod_notice_follows_heading(
        File::Spec->catfile(qw(lib Template EmbeddedPerl.pm)),
        '=head2 render_view',
        $pod_notice,
    ),
    'module POD marks typed views as experimental',
);
```

Remove the old duplicate module-POD assertion that followed the loop.

- [ ] **Step 3: Run the tests and verify RED**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t t/documentation.t
```

Expected: FAIL because `TypedViews.pod` does not exist and the old Markdown file
still exists.

- [ ] **Step 4: Create TypedViews POD with exact opening**

Create `lib/Template/EmbeddedPerl/Cookbook/TypedViews.pod`:

```pod
=head1 NAME

Template::EmbeddedPerl::Cookbook::TypedViews - Refactor Contacts into typed views

=head1 DESCRIPTION

B<Experimental:> Typed view support, including C<render_view>, C<view>,
C<view_namespace>, and C<view_factory>, may change as real-world integration
needs become clearer.

This document refactors the application from
L<Template::EmbeddedPerl::Tutorial>. It uses Moo to keep the examples concise,
but Template::EmbeddedPerl accepts any blessed view object and does not require
Moo at runtime.
```

- [ ] **Step 5: Write the typed refactor chapters**

Use these exact top-level headings:

```pod
=head1 WHY INTRODUCE A TYPED VIEW?
=head1 THE ROOT VIEW
=head1 TYPED CHILD VIEWS
=head1 WRAPPER VIEWS
=head1 INJECTING ROOT AND PARENT
=head1 COMPOSING THE VIEW TREE
=head1 CHOOSING BETWEEN BOTH DESIGNS
=head1 FAILURES AND REUSE
=head1 SEE ALSO
```

Use the complete Task 4 files as the canonical example. Explain:

- argument plumbing in the untyped item versus object attributes;
- root `render_view` and lexical `$self`;
- package segment snake-case convention;
- `ContactItem::template` explicit override precedence;
- `view 'HTML::Page', ..., sub ($page) { ... }` callback scope;
- caller `$self` in the wrapper body and Page `$self` in `html/page.epl`;
- exact `$class`, `$values`, and `$context` factory parameters;
- root and parent identities shown by Task 4 tests;
- preconstructed child factory bypass;
- helpers, untyped layout, and named content in typed rendering;
- cycles, one render stack, cleanup, and engine reuse after failure;
- when untyped partials/layouts remain preferable.

Migrate any unique, still-correct explanation from the old Markdown cookbook,
but do not preserve its unrelated example class tree.

- [ ] **Step 6: Remove the Markdown source and verify**

Delete:

```text
docs/cookbook/typed-views.md
```

Run:

```bash
perlbrew exec --with perl-5.40.0@default podchecker lib/Template/EmbeddedPerl/Cookbook/TypedViews.pod
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t t/documentation.t t/typed_view.t
```

Expected: POD syntax OK and all tests PASS.

- [ ] **Step 7: Commit Task 5**

```bash
git add lib/Template/EmbeddedPerl/Cookbook/TypedViews.pod t/cookbook_examples.t t/documentation.t
git add -u docs/cookbook/typed-views.md
git commit -m "docs: migrate typed-view cookbook to POD"
```

---

### Task 6: Integrate README, Distribution Contents, And Final Verification

**Files:**
- Modify: `README.mkdn`
- Modify: `dist.ini`
- Modify: `t/cookbook_examples.t`

**Interfaces:**
- Consumes: all POD and example paths from Tasks 1-5.
- Produces: README learning path using perldoc package names.
- Produces: built distribution with POD/examples included and `docs/` excluded.

- [ ] **Step 1: Add failing README navigation assertions**

Before `done_testing` in `t/cookbook_examples.t`, add:

```perl
my $readme = read_file(File::Spec->catfile($root, 'README.mkdn'));
for my $document (
    'Template::EmbeddedPerl::Tutorial',
    'Template::EmbeddedPerl::Cookbook',
    'Template::EmbeddedPerl::Cookbook::TypedViews',
) {
    like($readme, qr/perldoc \Q$document\E/, "README points to $document with perldoc");
}
unlike(
    $readme,
    qr{docs/cookbook/typed-views\.md},
    'README no longer links to the pruned Markdown cookbook',
);

for my $relative (
    'examples/contacts/untyped/app.pl',
    'examples/contacts/untyped/lib/Contacts/Untyped/App.pm',
    'examples/contacts/untyped/templates/pages/contacts.epl',
    'examples/contacts/untyped/templates/contacts/item.epl',
    'examples/contacts/untyped/templates/layouts/application.epl',
    'examples/contacts/typed/app.pl',
    'examples/contacts/typed/lib/Contacts/Typed/App.pm',
    'examples/contacts/typed/lib/Contacts/Typed/View/HTML/ContactList.pm',
    'examples/contacts/typed/lib/Contacts/Typed/View/HTML/Page.pm',
    'examples/contacts/typed/lib/Contacts/Typed/View/HTML/ContactItem.pm',
    'examples/contacts/typed/lib/Contacts/Typed/View/HTML/Badge.pm',
    'examples/contacts/typed/templates/html/contact_list.epl',
    'examples/contacts/typed/templates/html/page.epl',
    'examples/contacts/typed/templates/contacts/item.epl',
    'examples/contacts/typed/templates/contacts/badge.epl',
    'examples/contacts/typed/templates/layouts/application.epl',
) {
    my $path = File::Spec->catfile($root, split m{/}, $relative);
    ok(-e $path, "cookbook reference exists: $relative");
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t
```

Expected: FAIL because README does not yet contain the three perldoc commands.

- [ ] **Step 3: Add the README learning path**

Add a `# LEARNING PATH` section after DESCRIPTION and before ACKNOWLEDGEMENTS:

```markdown
# LEARNING PATH

Start with the framework-neutral Contacts tutorial:

    perldoc Template::EmbeddedPerl::Tutorial

For copyable solutions to specific template tasks:

    perldoc Template::EmbeddedPerl::Cookbook

For the experimental typed-view and wrapper-view refactor:

    perldoc Template::EmbeddedPerl::Cookbook::TypedViews

The complete runnable applications are under `examples/contacts/untyped` and
`examples/contacts/typed`.
```

Replace every remaining `docs/cookbook/typed-views.md` link with the appropriate
POD package name or perldoc command. Keep the exact typed-view experimental
notice in the README.

- [ ] **Step 4: Retain the distribution prune rule**

Ensure `dist.ini` contains:

```ini
[PruneFiles]
match = ^(CLAUDE|COPILOT|AI).*\.md$
match = ^docs/
filename = app_spec.txt
```

This is the already-approved working-tree change. Do not add rules excluding
`examples/` or installed `.pod` files.

- [ ] **Step 5: Run focused documentation verification**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t t/documentation.t
perlbrew exec --with perl-5.40.0@default podchecker lib/Template/EmbeddedPerl/Tutorial.pod
perlbrew exec --with perl-5.40.0@default podchecker lib/Template/EmbeddedPerl/Cookbook.pod
perlbrew exec --with perl-5.40.0@default podchecker lib/Template/EmbeddedPerl/Cookbook/TypedViews.pod
perlbrew exec --with perl-5.40.0@default perldoc -Ilib -l Template::EmbeddedPerl::Tutorial
perlbrew exec --with perl-5.40.0@default perldoc -Ilib -l Template::EmbeddedPerl::Cookbook
perlbrew exec --with perl-5.40.0@default perldoc -Ilib -l Template::EmbeddedPerl::Cookbook::TypedViews
```

Expected: all tests PASS, all three POD files report syntax OK, and all three
perldoc commands print the corresponding `.pod` path under `lib/`.

- [ ] **Step 6: Build and inspect the distribution**

Create a temporary destination and build:

```bash
BUILD_DIR=$(mktemp -d /tmp/template-embeddedperl-cookbook.XXXXXX)
perlbrew exec --with perl-5.40.0@default dzil build --in "$BUILD_DIR"
```

Verify required files are in `MANIFEST`:

```bash
rg '^lib/Template/EmbeddedPerl/(Tutorial|Cookbook|Cookbook/TypedViews)\.pod$' "$BUILD_DIR/MANIFEST"
rg '^examples/contacts/(untyped|typed)/' "$BUILD_DIR/MANIFEST"
```

Verify no internal docs ship:

```bash
if rg '^docs(?:/|$)' "$BUILD_DIR/MANIFEST"; then exit 1; fi
```

Expected: three POD paths and both example trees are present; no `docs/` path is
present.

- [ ] **Step 7: Run the complete regression suite**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lr t
git diff --check
git status --short
```

Expected: all tests PASS, no whitespace errors, and only intended task files are
modified or staged. Ignore no unrelated user changes.

- [ ] **Step 8: Commit Task 6**

```bash
git add README.mkdn dist.ini t/cookbook_examples.t
git commit -m "docs: publish cookbook learning path"
```

---

## Final Review Checklist

- [ ] The tutorial reads coherently from first render through abstraction choice.
- [ ] The cookbook recipes are task-oriented rather than a second API inventory.
- [ ] TypedViews uses the same Contacts application and preserves the exact experimental notice.
- [ ] Complete examples run directly from their shipped paths.
- [ ] Untyped and typed outputs are byte-for-byte identical.
- [ ] Moo is described as optional to the engine.
- [ ] All POD links resolve by package name.
- [ ] README contains all three perldoc commands and no stale Markdown link.
- [ ] The old Markdown cookbook is deleted only after migration.
- [ ] `docs/` is absent from the built distribution.
- [ ] Installed POD and both example trees are present in the built distribution.
- [ ] No template engine production code changed.
- [ ] Full suite, POD checks, Dist::Zilla build, and diff checks pass.
