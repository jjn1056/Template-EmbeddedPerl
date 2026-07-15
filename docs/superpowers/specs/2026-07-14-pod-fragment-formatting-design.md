# POD Fragment Formatting Design

## Problem

Installed POD uses bold labels such as `B<Fragment: application fixture>`
immediately followed by indented example text. Without a blank POD paragraph,
renderers parse the label and example as one ordinary paragraph. The result is
flattened code instead of a separate verbatim block.

## Scope

Apply one formatting rule consistently to:

- `lib/Template/EmbeddedPerl/Tutorial.pod`
- `lib/Template/EmbeddedPerl/Cookbook.pod`
- `lib/Template/EmbeddedPerl/Cookbook/TypedViews.pod`

The rule covers every bold `Fragment:` marker and every `Complete scratch
file:` marker that introduces an indented example. Engine behavior, example
content, headings, public APIs, and prose remain unchanged.

## Design

Keep the existing bold labels. Insert one blank line after each marker before
the indented example. This creates two POD paragraphs: a label paragraph and a
verbatim code block.

Do not convert labels to headings or list items. Those structures would give
small examples unnecessary navigational weight and would change the documents'
visual hierarchy.

## Tests

Add focused documentation coverage that:

1. Finds every `Fragment:` and `Complete scratch file:` marker in the three
   installed POD files.
2. Requires a blank line between each marker and the following indented block.
3. Renders representative POD through `Pod::Simple::HTML` and verifies that a
   fragment label is followed by a separate `<pre>` block rather than flattened
   into the label paragraph.
4. Runs `podchecker` for all three installed documents.
5. Runs the full test suite to catch unrelated documentation regressions.

## Acceptance Criteria

- Every labeled example renders as a distinct verbatim block.
- No label is joined to its first code line.
- All three installed POD files pass syntax checks.
- Existing cookbook and documentation tests continue to pass.
- The change contains no template-engine behavior modifications.
