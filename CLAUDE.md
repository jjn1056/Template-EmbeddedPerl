# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Template-EmbeddedPerl is a Perl CPAN module providing an embedded Perl template engine with flexible block capture syntax. It uses PPI (Perl Parser Infrastructure) to parse template code and detect block structures, enabling natural callback syntax that other template engines struggle with.

## Build & Test Commands

```bash
# Install dependencies
cpanm --installdeps .

# Run all tests
prove -l t/*.t

# Run individual test
prove -l t/basic.t

# Verbose output
prove -lv t/basic.t

# Build/release with Dist::Zilla
dzil build
dzil test
dzil release
```

## Debug Mode

```bash
DEBUG_TEMPLATE_EMBEDDED_PERL=1 perl script.pl
```

Shows compiled template code for debugging.

## Architecture

### Core Modules

- **lib/Template/EmbeddedPerl.pm** - Main template engine (parsing, compilation, execution). Uses PPI to detect control blocks vs value-returning blocks.
- **lib/Template/EmbeddedPerl/Compiled.pm** - Wrapper for compiled templates with `render(@args)` method
- **lib/Template/EmbeddedPerl/SafeString.pm** - Overloaded string object for HTML safety (prevents double-escaping)
- **lib/Template/EmbeddedPerl/Utils.pm** - Utility functions: `escape_javascript`, `uri_escape`, `normalize_linefeeds`, `generate_error_message`

### Template Syntax

- `<%= expr %>` - Evaluate and output expression
- `<% code %>` - Execute Perl code, no output
- `% code` / `%= expr` - Line-oriented shorthand
- `<%= expr =%>` - Trim trailing whitespace
- `# comment` - Comment line
- Block capture: `<%= helper(sub { %> content <% }) %>`

### Key Features

- **Block capture** - Core differentiator using PPI parsing to detect `sub`, `map`, `grep` blocks
- **Auto-escaping** - `auto_escape` option with `raw()`, `safe()`, `safe_concat()` helpers
- **Object self-escaping** - Objects with `to_safe_string()` method can control their own escaping
- **Variable interpolation mode** - Optional `$var` interpolation in text

### Test Files

- `t/basic.t` - Core functionality
- `t/interpolated.t` - Variable interpolation with dereferencing
- `t/if.t` - Control structures (if/elsif/else)
- `t/util.t` - JavaScript escape edge cases
- `t/stringification.t` - Object stringification with auto_escape
- `t/crazy.t` - Complex block capture scenarios
- `t/ff.t` - Form builder integration

## Key Dependencies

- PPI (Perl parser for block detection)
- HTML::Escape (entity escaping)
- Regexp::Common (balanced delimiter patterns)
- JSON::MaybeXS (JavaScript escaping)
