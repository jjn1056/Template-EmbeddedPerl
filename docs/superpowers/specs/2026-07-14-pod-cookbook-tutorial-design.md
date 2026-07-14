# POD Cookbook And Contacts Tutorial Design

Date: 2026-07-14

Status: Approved for implementation planning

## Purpose

Template::EmbeddedPerl needs a progressive learning path in addition to its
API-oriented README and existing advanced typed-view material.

The documentation will teach a Perl developer who is new to the engine how to
build a small, complete Contacts application. It will also provide independent
recipes for existing users and an advanced refactor for framework authors using
typed views, wrapper views, and dependency injection.

The documentation must be Perl POD stored under `lib/` so it is installed with
the distribution and discoverable through `perldoc`. The repository's `docs/`
tree is internal project documentation and is pruned from release artifacts.

## Audience Priority

The documentation serves three audiences in this order:

1. Perl developers new to Template::EmbeddedPerl.
2. Existing users looking for a copyable recipe.
3. Framework authors integrating typed views and application dependencies.

The opening language, reading order, and first examples must serve newcomers.
Recipe lookup and framework integration remain first-class, but they must not
make the initial tutorial feel advanced or framework-specific.

## Learning Model

Use one evolving Contacts application as the tutorial spine. Supplement it
with independent recipes, then refactor the same application into typed views.

This combines three useful modes:

- a coherent start-to-finish tutorial;
- direct lookup for readers who already know what they need;
- a concrete comparison between untyped and typed application design.

The Contacts application is framework-neutral. It uses in-memory data and
renders HTML from a Perl script. It does not require a web framework, database,
network service, or application server.

## Documentation Layout

Create these installed POD documents:

```text
lib/Template/EmbeddedPerl/
  Tutorial.pod
  Cookbook.pod
  Cookbook/
    TypedViews.pod
```

Create these runnable examples:

```text
examples/contacts/
  untyped/
    app.pl
    lib/
    templates/
  typed/
    app.pl
    lib/
    templates/
```

Create one primary verification file:

```text
t/cookbook_examples.t
```

### Template::EmbeddedPerl::Tutorial

`Template::EmbeddedPerl::Tutorial` is the guided newcomer path. It builds the
untyped Contacts application progressively and ends with a production-oriented
configuration and troubleshooting workflow.

The tutorial should be readable in order. It may link to recipes for optional
details, but a reader must not need to jump among documents to complete the
application.

### Template::EmbeddedPerl::Cookbook

`Template::EmbeddedPerl::Cookbook` is both the recipe collection and navigation
hub. It starts with a short reading guide:

- new users should read `Template::EmbeddedPerl::Tutorial`;
- readers solving a specific problem can use the recipe index;
- framework authors can continue to
  `Template::EmbeddedPerl::Cookbook::TypedViews`.

Recipes must be independently understandable, short, and copyable. They should
link back to the tutorial when a concept needs broader context.

### Template::EmbeddedPerl::Cookbook::TypedViews

`Template::EmbeddedPerl::Cookbook::TypedViews` is the advanced continuation.
It refactors the same Contacts application from untyped templates into Moo view
classes, convention-resolved templates, typed children, and wrapper views.

The document must retain the experimental notice for typed-view support. It
must state that Moo is used for concise examples but is not required by the
engine; any blessed object is supported.

## README Integration

Keep `README.mkdn` primarily as reference documentation. Add a prominent
learning section near the synopsis or description with commands such as:

```text
perldoc Template::EmbeddedPerl::Tutorial
perldoc Template::EmbeddedPerl::Cookbook
perldoc Template::EmbeddedPerl::Cookbook::TypedViews
```

Replace Markdown cookbook links with POD links or perldoc guidance where
appropriate. Do not duplicate the tutorial in the README.

## Tutorial Curriculum

The guided tutorial follows this progression.

### 1. Install And Render The First Template

- Load Template::EmbeddedPerl.
- Render a string containing one expression.
- Explain the distinction between compiling and rendering.
- Show the output immediately.

### 2. Create The Contacts Application

- Introduce the example directory tree.
- Configure ordered template directories.
- Render a file-backed contacts page.
- Use in-memory contact hashes as data.

### 3. Use Smart Lines And Named Arguments

- Enable `smart_lines`.
- Introduce `% args` as the template contract.
- Pass named values to `render`.
- Explain required arguments and unknown-argument errors.

### 4. Add Defaults And Lazy Defaults

- Show scalar defaults.
- Show coderef lazy defaults.
- Explain that explicit `undef` is supplied and does not invoke a lazy default.
- Keep the example tied to a visible page title or heading.

### 5. Escape Output Safely

- Enable `auto_escape` for HTML output.
- Demonstrate escaping with contact data containing markup.
- Explain `raw`, safe strings, and why rendered composition helpers are not
  escaped a second time.
- State that templates execute trusted arbitrary Perl and are not a security
  sandbox.

### 6. Extract A Partial

- Move one contact row into a partial.
- Give the partial its own `% args` contract.
- Render a list through repeated partial calls.
- Explain when a partial is preferable to a typed view.

### 7. Add A Layout

- Register an application layout.
- Use `yield` for the page body.
- Give the layout independent arguments.
- Explain layout ordering and deferred wrapping.

### 8. Add Named Content

- Add page-specific head content with `content_for`.
- Replace a default block with `content_replace`.
- Check a block with `has_content`.
- Yield named content from the layout.

### 9. Add Application Helpers

- Configure a helper in Perl.
- Show the engine as the helper's first argument.
- Keep business or formatting logic out of the template where practical.
- Explain helper override and reuse at a high level.

### 10. Diagnose Failures

- Trigger one compile error.
- Trigger one runtime error.
- Trigger one warning.
- Show source names, exact template lines, nearby excerpts, and render stacks.
- Explain why file-backed templates produce the best diagnostics.

### 11. Reuse And Production Configuration

- Explain compiled-template reuse.
- Explain `use_cache` for repeated `render` or compilation workflows.
- Cover persistent-process expectations.
- Summarize `preamble`, custom helpers, ordered directories, and trusted-source
  requirements without turning the tutorial into API reference.

### 12. Choose The Next Abstraction

- Summarize when plain templates are enough.
- Summarize when partials and layouts are enough.
- Introduce typed views as an optional next step for object-backed UI models.
- Link to `Template::EmbeddedPerl::Cookbook::TypedViews`.

## Recipe Catalog

`Template::EmbeddedPerl::Cookbook` should contain concise recipes grouped by
reader intent rather than by internal method name.

### Rendering And Loading

- Render a template string.
- Render a file from ordered template directories.
- Render from a filehandle.
- Render a package `__DATA__` section with `from_data`.
- Reuse a compiled template.
- Use the compile cache safely.

### Template Inputs

- Declare required named arguments.
- Add scalar defaults.
- Add lazy defaults.
- Distinguish an absent value from explicit `undef`.
- Validate unexpected arguments.

### Output And Escaping

- Enable automatic HTML escaping.
- Return trusted raw HTML.
- Work with safe-string objects.
- Escape a URL value.
- Escape a JavaScript string value.
- Control expression flattening.

### Composition

- Render a partial.
- Register one or more layouts.
- Yield a page body.
- Capture, replace, test, and yield named content.
- Use a wrapper body.

### Syntax And Formatting

- Use smart code and expression lines.
- Trim expression values.
- Trim whitespace after a tag.
- Suppress a newline after a tag.
- Escape literal template markers.
- Change open, close, expression, line, and comment markers.
- Enable interpolation and escape a literal dollar sign.

### Helpers And Configuration

- Add an application helper.
- Override a default helper.
- Add modules or language features through `preamble`.
- Add per-render setup through `prepend`.
- Locate templates relative to a package.

### Testing And Troubleshooting

- Test a compiled template with Test::Most.
- Test exact escaped output.
- Test a partial or layout in isolation.
- Supply a useful source name to `from_string` or `from_fh`.
- Read a compile diagnostic and render stack.
- Inspect generated Perl with `DEBUG_TEMPLATE_EMBEDDED_PERL`.

Recipes that would merely repeat one line of API reference should be omitted.
Each recipe must solve a concrete user task.

## Typed-View Refactor Curriculum

The advanced POD evolves the completed Contacts example instead of introducing
an unrelated object hierarchy.

### 1. Why Introduce A Typed View

- Identify the point where a growing argument list becomes an object contract.
- Explain lexical `$self` in typed templates.
- Keep simple partials and layouts untyped where that remains clearer.

### 2. Build The Root View

- Create a Moo root view containing title and contacts.
- Configure `view_namespace`.
- Render it with `render_view`.
- Resolve its template through package-to-snake-case convention.

### 3. Add Typed Child Views

- Render a preconstructed child object.
- Render a logical child name.
- Show explicit `template` override precedence.
- Contrast typed children with untyped partials.

### 4. Add A Wrapper View

- Use a final coderef body with `view`.
- Show caller `$self` inside the body callback.
- Show wrapper `$self` inside the wrapper template.
- Yield the captured body.

### 5. Inject Root And Parent

- Configure `view_factory`.
- Explain `$class`, `$args`, and `$context`.
- Inject `root` and `parent` into logical children.
- Show that preconstructed objects bypass the factory.

### 6. Compose A Real View Tree

- Render nested child views from a wrapper.
- Use the same ordered template directories.
- Use helpers, untyped partials, and layouts from typed templates.
- Explain render-frame cleanup, cycle detection, and failure reuse.

### 7. Compare Both Designs

- List the final untyped and typed responsibilities side by side.
- Recommend untyped templates for small local composition.
- Recommend typed views when constructor validation, reusable view behavior, or
  dependency injection earns the extra structure.
- Repeat that typed-view support is experimental.

## Runnable Example Design

Both example applications use the same deterministic in-memory contact data
and produce equivalent HTML.

Each example should expose an application module with a small `render` method.
The executable is a thin wrapper:

```text
app.pl -> construct application -> render -> print
```

This makes examples useful from the command line while allowing tests to call
the application directly without subprocess-only assertions.

Use distinct package namespaces for the two applications, for example:

```text
Contacts::Untyped::App
Contacts::Typed::App
Contacts::Typed::View::HTML::ContactList
```

The typed example uses Moo for concise classes. Its POD must include the Moo
installation requirement for readers running that example and must explain
that Moo is optional to Template::EmbeddedPerl itself.

The examples are complete endpoint applications, not a directory per tutorial
step. Tutorial sections show focused excerpts and explain how the endpoint is
built progressively.

## Example Output Contract

The untyped and typed examples should render semantically and byte-for-byte
equivalent HTML for the shared fixture data unless a typed-only demonstration
requires a clearly documented addition.

The output must visibly demonstrate:

- automatic escaping;
- at least two contacts;
- one partial or typed contact item;
- one application layout;
- one named content block;
- one application helper;
- a title or heading default;
- wrapper content in the typed version.

Deterministic output makes documentation tests simple and catches accidental
whitespace or escaping drift.

## Verification Strategy

Create `t/cookbook_examples.t` to exercise the real checked-in applications.

The test must verify:

- the untyped application renders its expected output;
- the typed application renders its expected output;
- both applications satisfy the intended parity contract;
- untrusted-looking contact values are escaped exactly once;
- a lazy argument default is evaluated only when absent;
- helpers, partials, layouts, and named content work in the untyped example;
- typed children, convention lookup, wrapper scope, root, parent, and
  `view_factory` work in the typed example;
- representative compile and runtime failures retain useful source locations;
- each path referenced by the POD exists;
- both `app.pl` entry points execute successfully.

Run `podchecker` against:

```text
lib/Template/EmbeddedPerl/Tutorial.pod
lib/Template/EmbeddedPerl/Cookbook.pod
lib/Template/EmbeddedPerl/Cookbook/TypedViews.pod
```

Complete code examples should be labeled as runnable. Incomplete excerpts must
be labeled as fragments so readers do not mistake them for standalone files.

Tests should validate behavior rather than snapshot every line of POD. The real
example files are authoritative. POD excerpts must be reviewed against those
files as part of documentation changes.

## Existing Documentation Migration

Migrate all still-relevant content from
`docs/cookbook/typed-views.md` into the installed POD documents.

After migration:

- remove the old Markdown cookbook;
- update README links;
- update tests that currently require the Markdown file or inspect its notice;
- preserve the exact experimental typed-view notice in the new POD;
- avoid maintaining Markdown and POD copies of the same examples.

Internal design specifications under `docs/superpowers/` remain unchanged and
continue to be excluded from the distribution through `dist.ini`.

## Writing Style

- Lead with a working result, then explain it.
- Prefer short paragraphs and concrete code.
- Use one term consistently for each concept.
- Label filenames before template blocks.
- Show expected output after important steps.
- Explain why an abstraction is introduced, not only how to call it.
- Keep reference-like option inventories in the README or recipe POD.
- Avoid framework assumptions in the beginner tutorial.
- Mark trusted-output and arbitrary-Perl security boundaries explicitly.
- Keep typed-view experimental language visible and consistent.

## Error Handling In The Tutorial

Failure examples must be deliberate and recoverable. Do not leave the example
application itself in a failing state.

The tutorial should show captured diagnostic excerpts for:

- a misspelled Perl variable causing a compile error;
- a method call on an invalid value causing a runtime error;
- a template warning;
- a nested typed-view failure with a render stack.

Expected output should focus on stable source and template-line information,
not unstable eval identifiers or internal wrapper line numbers.

## Dependencies And Distribution

- The untyped example adds no runtime dependencies.
- The typed example uses the existing test dependency on Moo.
- The POD documents live under `lib/` and are included in release artifacts.
- The runnable `examples/contacts` tree should also be included in release
  artifacts.
- The internal `docs/` tree remains pruned.
- No web framework or database dependency is introduced.

## Non-Goals

- Do not turn the tutorial into exhaustive API documentation.
- Do not introduce a PSGI server, database, router, or form framework.
- Do not design new template syntax.
- Do not stabilize the experimental typed-view API as part of documentation.
- Do not rewrite the template compiler.
- Do not maintain duplicate Markdown and POD cookbook content.
- Do not require every tutorial intermediate step to be a separate checked-in
  application snapshot.

## Acceptance Criteria

- [ ] All three POD documents exist under the specified package paths.
- [ ] `perldoc` can locate each document by package name.
- [ ] The Tutorial provides a coherent newcomer path through the complete
      untyped Contacts application.
- [ ] The Cookbook contains independent recipes grouped by user intent.
- [ ] TypedViews refactors the same application and preserves the experimental
      notice.
- [ ] Complete untyped and typed example applications are checked in and run.
- [ ] Both applications use framework-neutral in-memory data.
- [ ] The typed example uses Moo while documenting that Moo is optional.
- [ ] Example output covers escaping, composition, helpers, defaults, and
      wrappers.
- [ ] `t/cookbook_examples.t` verifies both applications and their parity.
- [ ] Representative diagnostic examples are tested.
- [ ] Every referenced example path exists.
- [ ] README learning links point to installed POD rather than pruned Markdown.
- [ ] The old Markdown cookbook is removed after migration.
- [ ] `podchecker` passes for all new POD.
- [ ] The complete existing test suite passes.
- [ ] A Dist::Zilla build includes the POD and examples but excludes `docs/`.

## Implementation Boundary

This design is documentation and example work. It must not change template
engine behavior. If writing the examples reveals an engine bug, capture the bug
in a regression test and handle it as a separate change rather than silently
altering the cookbook scope.
