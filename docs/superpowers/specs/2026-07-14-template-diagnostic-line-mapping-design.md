# Template Diagnostic Line Mapping Design

**Date:** 2026-07-14
**Status:** Approved design

## Goal

Make compile errors, runtime exceptions, and native Perl warnings report the
correct template source and physical line after comment removal, smart-line
rewriting, wrapper setup, and cache reuse. Preserve rendered output and all
public APIs.

## Confirmed Failures

The current compiler relies on generated Perl retaining the same newline count
as the input template. Three transformations violate that assumption:

1. A template comment ending in `\` becomes an escaped newline. The compiler
   removes every such newline but emits only one replacement newline because it
   treats the substitution count as a boolean. Two or more continued comments
   therefore move diagnostics backward.
2. With `smart_lines => 1`, the smart-line rewrite consumes each directive's
   physical newline to suppress output. It also removes that newline from the
   generated Perl, so consecutive smart directives collapse onto one diagnostic
   line.
3. Multiline `preamble` or `prepend` code adds generated Perl lines before the
   template body, moving template diagnostics forward.

Warnings currently expose an eval filename such as `(eval 52)` even when the
compiled template has a source name.

## Chosen Approach

Preserve the source newline structure that the compiler already uses, then add
one native Perl `#line` directive immediately before generated template code.
This is narrower than redesigning parsed blocks around a full source map and
safer than intercepting and rewriting warnings after execution.

## Source-Line Preservation

### Continued Comment Lines

The text compiler will retain the integer count returned by each escaped-line
substitution. It will emit that many generated Perl newlines, not one newline
for any nonzero count. Removing one or several comment continuations must still
produce the same rendered output as today.

### Smart Lines

When a smart directive has a physical trailing newline, the rewrite will retain
that newline as the existing escaped-newline sentinel after the generated close
tag. The text compiler consumes the sentinel without adding output while
leaving one newline in generated Perl. A final smart directive without a
trailing newline receives no synthetic line.

Legacy line syntax and ordinary inline tags keep their existing behavior.

## Native Diagnostic Source

The generated wrapper will place a line directive after `preamble` and
`prepend` setup and immediately before the template body:

```perl
#line 1 "pages/contact.epl"
```

This resets numbering after multiline wrapper configuration and makes Perl
warnings identify the template source directly. Templates without a source use
`unknown`.

An internal source-label helper will make line-directive labels safe before
embedding them in generated Perl. Normal Unix paths, including spaces, remain
unchanged. Each run of carriage returns or newlines becomes one space, each
double quote becomes an apostrophe, and every other ASCII control character
becomes `?`. This keeps the transformation deterministic and prevents a
caller-provided source from terminating or injecting generated code.

Warnings that let Perl append a location will therefore identify the template
source and exact line. A warning string ending in a newline continues to follow
normal Perl behavior and receives no automatically appended location.

## Error Decoration

`generate_error_message` will recognize both legacy eval locations and the
sanitized template source emitted by the line directive as template-originated
diagnostics. Compile and runtime errors will continue to include the source,
the exact line, and nearby original template lines. Errors originating in real
module or helper files remain untouched.

Render-stack decoration remains unchanged.

## Cache Correctness

The compiled coderef now contains its diagnostic source label. The in-memory
compiled-cache key must therefore include both template content and diagnostic
source. Identical content compiled for two source names must produce separate
code entries so warnings cannot report the first page's name for the second
page.

Repeated compilation of the same content and source remains cacheable.

## Regression Tests

Create `t/diagnostic_lines.t` with table-driven helpers for compile errors,
runtime exceptions, and captured warnings. The suite will check exact source
and line reporting for:

- an ordinary inline template baseline;
- ordinary, indented, escaped, and middle-of-template comments;
- one, two, and three comments ending in `\`;
- custom comment markers and CRLF input;
- consecutive smart code and expression directives;
- smart directives mixed with ordinary and continued comments;
- custom smart-line markers;
- multiline Perl blocks;
- trim-close tags and escaped output newlines;
- interpolation and named `args` rewriting;
- multiline `preamble` and `prepend` code;
- identical cached content compiled under different sources;
- normal source paths containing spaces and source labels containing unsafe
  line-directive characters.

The failing cases must be added and observed failing before production code is
changed. Existing passing cases serve as guards against broad arithmetic fixes
that damage currently correct mappings.

Existing output tests in `t/basic.t`, `t/smart_lines.t`, `t/newline_trim.t`, and
the full suite must remain unchanged and pass. Add focused output assertions
only where the new sentinel or newline-count logic could otherwise change
rendered whitespace.

## Scope

- No public methods or configuration keys are added.
- Rendered output and whitespace semantics do not change.
- Template comment, smart-line, trim, interpolation, argument, partial, layout,
  and typed-view syntax do not change.
- Warning strings that suppress Perl's location by ending in a newline do not
  gain a synthetic location.
- A full per-block source-map redesign is out of scope unless the chosen repair
  cannot satisfy the regression matrix without changing output.

## Verification

1. Run the focused diagnostic test and record the expected RED failures.
2. Implement one root-cause repair at a time and keep the focused suite green.
3. Run the existing comment, smart-line, newline-trim, argument, regression,
   composition-error, and template-lookup tests.
4. Run the complete Perl 5.40 suite.
5. Run POD and Git whitespace checks if documentation or POD changes are made.
