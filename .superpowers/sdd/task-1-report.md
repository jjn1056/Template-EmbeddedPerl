# Task 1 Report: Document Typed Views As Experimental

## Implementation Summary

Added the approved experimental stability notice for typed view support to the README, typed-view cookbook, and module POD. Added documentation tests that preserve the exact Markdown and POD wording while allowing line wrapping. No runtime behavior, public API, template output, or untyped rendering behavior changed.

## Changed Files

- `t/documentation.t`: Added normalized-document checks for the two Markdown notices and the module POD notice.
- `README.mkdn`: Added the experimental notice at the `render_view` entry point.
- `docs/cookbook/typed-views.md`: Added the experimental notice at the Typed Views section.
- `lib/Template/EmbeddedPerl.pm`: Added the equivalent POD notice at `=head2 render_view`.
- `docs/superpowers/plans/2026-07-14-typed-view-experimental-notice.md`: Added the implementation plan required by the task.

## RED Verification

Command:

```text
perlbrew exec --with perl-5.40.0@default prove -lv t/documentation.t
```

Result: expected failure. Only the three new assertions failed:

```text
not ok 2 - README marks typed views as experimental
not ok 3 - cookbook marks typed views as experimental
not ok 4 - module POD marks typed views as experimental
Looks like you failed 3 tests of 17.
```

The remaining 14 existing assertions passed.

## GREEN Verification

Commands:

```text
perlbrew exec --with perl-5.40.0@default prove -lv t/documentation.t
perlbrew exec --with perl-5.40.0@default podchecker lib/Template/EmbeddedPerl.pm
```

Results:

- Focused documentation test: PASS, 17 tests, including all three new notice assertions.
- POD checker: `lib/Template/EmbeddedPerl.pm pod syntax OK`, exit 0.
- `podchecker` emitted the repository's pre-existing warning about a whitespace-only paragraph at line 1165.

## Full Verification

Commands:

```text
perlbrew exec --with perl-5.40.0@default prove -lr t
git diff --check
```

Results:

- Full suite: PASS, 20 files and 463 tests.
- `git diff --check`: PASS, no output.

## Self-Review

- Confirmed the exact approved wording and markup are present in all three user-visible documentation locations.
- Confirmed the test normalization only removes Markdown blockquote prefixes and whitespace differences.
- Confirmed the change is documentation and test-only; no runtime implementation was modified.
- Confirmed the experimental designation applies only to typed view support and does not label legacy or untyped rendering APIs.
- Commit created: `35da7aa docs: mark typed views experimental`.

## Concerns

The only concern is the pre-existing `podchecker` whitespace-only paragraph warning at line 1165. It does not affect POD validity or the exit status.

## Fix Report

- Exact change: Replaced the whole-file normalized substring checks in `t/documentation.t` with heading-scoped assertions. Markdown checks now require the notice to immediately follow the relevant heading as consecutive `>`-prefixed lines; the POD check now requires the notice to be the first paragraph after `=head2 render_view`. Whitespace is normalized and trimmed to preserve tolerance for harmless line wrapping.
- Verification of the finding: Before the fix, synthetic content with the notice moved after intervening usage text and synthetic content with the Markdown `>` prefixes removed were both accepted by the old matcher. The existing focused test also passed 17/17 before the fix, confirming the weakness was not exposed by the current fixtures.
- Focused command: `perlbrew exec --with perl-5.40.0@default prove -lv t/documentation.t`
- Focused result: PASS; 17 tests, 0 failures, all tests successful.
- Changed files: `t/documentation.t`; `.superpowers/sdd/task-1-report.md`.
- Commit: `7563d7d test: tighten typed view notice assertions`
- Concerns: No runtime files or documentation wording were changed. The pre-existing `podchecker` whitespace-only paragraph warning is unrelated to this fix.
