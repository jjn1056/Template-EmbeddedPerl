# Typed View Experimental Notice Design

**Date:** 2026-07-14
**Status:** Approved design

## Goal

Clearly mark typed view support as experimental without implying that the
stable untyped rendering and composition APIs are experimental.

## Wording

Use this notice in Markdown documentation:

> **Experimental:** Typed view support, including `render_view`, `view`,
> `view_namespace`, and `view_factory`, may change as real-world integration
> needs become clearer.

Use equivalent POD markup in the module documentation:

```pod
B<Experimental:> Typed view support, including C<render_view>, C<view>,
C<view_namespace>, and C<view_factory>, may change as real-world integration
needs become clearer.
```

## Placement

Add the notice at each primary typed-view entry point:

- In `README.mkdn`, immediately after the `render_view` heading and before its
  usage example.
- In `docs/cookbook/typed-views.md`, immediately after the `Typed Views`
  heading.
- In `lib/Template/EmbeddedPerl.pm`, immediately after the `render_view` POD
  heading and before its usage example.

## Scope

This is a documentation-only change. It does not alter runtime behavior,
public APIs, or template output. The notice applies only to typed view support;
ordinary templates, partials, layouts, and untyped rendering remain outside
the experimental designation.

## Verification

- Confirm all three documentation entry points contain the approved notice.
- Check the POD syntax.
- Run the complete test suite to catch documentation and distribution checks.
- Run Git whitespace checks on the final diff.
