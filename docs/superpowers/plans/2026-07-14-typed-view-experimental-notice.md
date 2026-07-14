# Typed View Experimental Notice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mark typed view support as experimental at all three primary documentation entry points without changing runtime behavior or labeling untyped composition APIs as experimental.

**Architecture:** Add executable documentation assertions that preserve the approved copy in Markdown and POD forms, then insert the notice beside the existing typed-view introductions. Keep the implementation documentation-only and use the existing `t/documentation.t` suite rather than introducing a new test file.

**Tech Stack:** Perl 5.40, Test::Most, Markdown, POD, `prove`, `podchecker`.

## Global Constraints

- Use this Markdown wording exactly:

  ```markdown
  **Experimental:** Typed view support, including `render_view`, `view`, `view_namespace`, and `view_factory`, may change as real-world integration needs become clearer.
  ```
- Use semantically equivalent POD markup with `B<Experimental:>` and `C<...>` around each API name.
- Apply the experimental designation only to typed view support.
- Do not change runtime behavior, public APIs, template output, ordinary templates, partials, layouts, or untyped rendering.

## File Structure

- Modify `t/documentation.t`: assert that the approved Markdown and POD notices remain present, allowing line wrapping while retaining emphasis and API-name markup.
- Modify `README.mkdn`: show the experimental notice at the `render_view` entry point.
- Modify `docs/cookbook/typed-views.md`: show the notice at the start of the typed-view cookbook section.
- Modify `lib/Template/EmbeddedPerl.pm`: show the equivalent notice in the `render_view` POD section.

---

### Task 1: Document Typed Views As Experimental

**Files:**
- Modify: `t/documentation.t:10-12`
- Modify: `README.mkdn:459`
- Modify: `docs/cookbook/typed-views.md:88`
- Modify: `lib/Template/EmbeddedPerl.pm:1447`

**Interfaces:**
- Consumes: the existing `t/documentation.t` test suite and the approved wording in `docs/superpowers/specs/2026-07-14-typed-view-experimental-notice-design.md`.
- Produces: three user-visible experimental notices protected by documentation tests.

- [ ] **Step 1: Write failing documentation assertions**

Add these helpers and assertions immediately after the cookbook-presence check in `t/documentation.t`:

```perl
sub normalized_document {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh or die "Cannot close $path: $!";
    $content =~ s/^\s*>\s?//gm;
    $content =~ s/\s+/ /g;
    return $content;
}

my $markdown_notice = q{**Experimental:** Typed view support, including }
    . q{`render_view`, `view`, `view_namespace`, and `view_factory`, may change }
    . q{as real-world integration needs become clearer.};
my $pod_notice = q{B<Experimental:> Typed view support, including }
    . q{C<render_view>, C<view>, C<view_namespace>, and C<view_factory>, may change }
    . q{as real-world integration needs become clearer.};

for my $document (
    [README => 'README.mkdn'],
    [cookbook => $cookbook],
) {
    ok(
        index(normalized_document($document->[1]), $markdown_notice) >= 0,
        "$document->[0] marks typed views as experimental",
    );
}

ok(
    index(
        normalized_document(File::Spec->catfile(qw(lib Template EmbeddedPerl.pm))),
        $pod_notice,
    ) >= 0,
    'module POD marks typed views as experimental',
);
```

- [ ] **Step 2: Run the focused test to verify the assertions fail**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/documentation.t
```

Expected: FAIL only the three new assertions named `README marks typed views as experimental`, `cookbook marks typed views as experimental`, and `module POD marks typed views as experimental` because the notices are not present yet.

- [ ] **Step 3: Add the approved notice to both Markdown entry points**

Immediately after `## render_view` in `README.mkdn` and immediately after `## Typed Views` in `docs/cookbook/typed-views.md`, add:

```markdown
> **Experimental:** Typed view support, including `render_view`, `view`,
> `view_namespace`, and `view_factory`, may change as real-world integration
> needs become clearer.
```

- [ ] **Step 4: Add the equivalent notice to the module POD**

Immediately after `=head2 render_view` in `lib/Template/EmbeddedPerl.pm`, add:

```pod
B<Experimental:> Typed view support, including C<render_view>, C<view>,
C<view_namespace>, and C<view_factory>, may change as real-world integration
needs become clearer.
```

- [ ] **Step 5: Run focused documentation and POD verification**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/documentation.t
perlbrew exec --with perl-5.40.0@default podchecker lib/Template/EmbeddedPerl.pm
```

Expected: `t/documentation.t` passes, including all three new notice assertions. `podchecker` reports `pod syntax OK`; the repository's pre-existing whitespace-only POD paragraph warning may still appear.

- [ ] **Step 6: Run the complete suite and diff checks**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lr t
git diff --check
```

Expected: all test files pass with three more assertions than the current 460-test baseline, and `git diff --check` produces no output.

- [ ] **Step 7: Commit the implementation**

```bash
git add t/documentation.t README.mkdn docs/cookbook/typed-views.md lib/Template/EmbeddedPerl.pm docs/superpowers/plans/2026-07-14-typed-view-experimental-notice.md
git commit -m "docs: mark typed views experimental"
```
