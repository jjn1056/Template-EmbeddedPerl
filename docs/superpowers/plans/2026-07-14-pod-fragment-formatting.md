# POD Fragment Formatting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render every labeled POD example as a separate verbatim code block instead of joining its first line to the label.

**Architecture:** Add one source-structure regression over all installed POD documents and one rendered-HTML regression for a representative tutorial fragment. Then apply the same blank-paragraph rule mechanically to every `Fragment:` and `Complete scratch file:` marker.

**Tech Stack:** Perl 5.40, Test::Most, Pod::Simple::HTML, Pod::Checker.

## Global Constraints

- Keep existing bold fragment labels and document hierarchy.
- Change only POD paragraph spacing; do not alter example code or prose.
- Cover Tutorial, Cookbook, and TypedViews POD consistently.
- Do not change template-engine behavior or public APIs.
- Use ASCII for all edits.
- Run Perl commands through `perlbrew exec --with perl-5.40.0@default`.

---

### Task 1: Separate Fragment Labels From Verbatim Blocks

**Files:**
- Modify: `t/cookbook_examples.t`
- Modify: `lib/Template/EmbeddedPerl/Tutorial.pod`
- Modify: `lib/Template/EmbeddedPerl/Cookbook.pod`
- Modify: `lib/Template/EmbeddedPerl/Cookbook/TypedViews.pod`

**Interfaces:**
- Consumes: installed POD source and `Pod::Simple::HTML`.
- Produces: a source invariant requiring a blank paragraph after every labeled example and rendered HTML containing distinct label and `<pre>` blocks.

- [ ] **Step 1: Add failing source and HTML regressions**

Add `use Pod::Simple::HTML;` to `t/cookbook_examples.t` and define:

```perl
sub malformed_labeled_verbatim_lines {
    my ($pod) = @_;
    my @lines = split /\n/, $pod, -1;
    my @malformed;

    for my $index (0 .. $#lines) {
        next unless $lines[$index] =~ /^B<(?:Fragment:|Complete scratch file:)/;
        push @malformed, $index + 1
            unless ($lines[$index + 1] // '') eq ''
                && ($lines[$index + 2] // '') =~ /^  \S/;
    }

    return \@malformed;
}

sub pod_html {
    my ($pod) = @_;
    my $html = '';
    my $parser = Pod::Simple::HTML->new;
    $parser->output_string(\$html);
    $parser->parse_string_document($pod);
    return $html;
}
```

After each installed POD file is read, assert:

```perl
is_deeply(
    malformed_labeled_verbatim_lines($pod),
    [],
    "$path separates labeled examples from verbatim blocks",
);
```

For the tutorial, also assert:

```perl
like(
    pod_html($tutorial),
    qr{<p><b>Fragment: application fixture</b></p>\s*<pre>\s*sub contacts \{},
    'rendered tutorial separates the fragment label from its code block',
);
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t
```

Expected: FAIL. Each installed POD reports marker line numbers lacking the blank paragraph, and the rendered tutorial does not contain a separate `<pre>` block after the application-fixture label.

- [ ] **Step 3: Apply the POD paragraph boundary consistently**

In all three POD files, transform every occurrence of:

```pod
B<Fragment: description>
  code
```

or:

```pod
B<Complete scratch file: C<path>>
  code
```

into:

```pod
B<Fragment: description>

  code
```

Do not change marker text or example content.

- [ ] **Step 4: Run focused formatting verification and verify GREEN**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/cookbook_examples.t
perlbrew exec --with perl-5.40.0@default podchecker \
  lib/Template/EmbeddedPerl/Tutorial.pod \
  lib/Template/EmbeddedPerl/Cookbook.pod \
  lib/Template/EmbeddedPerl/Cookbook/TypedViews.pod
```

Expected: the focused test passes all assertions and all three POD files report `pod syntax OK`.

- [ ] **Step 5: Run the full regression suite**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lr t
git diff --check
```

Expected: all tests pass and `git diff --check` prints no errors.

- [ ] **Step 6: Commit the fix**

```bash
git add \
  t/cookbook_examples.t \
  lib/Template/EmbeddedPerl/Tutorial.pod \
  lib/Template/EmbeddedPerl/Cookbook.pod \
  lib/Template/EmbeddedPerl/Cookbook/TypedViews.pod \
  docs/superpowers/plans/2026-07-14-pod-fragment-formatting.md
git commit -m "docs: fix fragment code block formatting"
```
