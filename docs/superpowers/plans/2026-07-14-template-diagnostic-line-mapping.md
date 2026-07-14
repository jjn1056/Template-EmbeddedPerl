# Template Diagnostic Line Mapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make template compile errors, runtime exceptions, and native Perl warnings report the exact template source and physical line across comments, smart lines, wrapper setup, and cache reuse without changing rendered output.

**Architecture:** Preserve every physical template newline in generated Perl, using escaped-newline sentinels when output whitespace must still be consumed. Reset Perl's diagnostic location with one sanitized `#line` directive immediately before the generated template body, and include that source label in the compiled-cache key so cached coderefs cannot retain another page's name.

**Tech Stack:** Perl 5.40, Template::EmbeddedPerl, PPI, Test::Most, Digest::MD5, `prove`.

## Global Constraints

- No public methods or configuration keys are added.
- Rendered output and whitespace semantics do not change.
- Compile errors, runtime exceptions, and location-bearing native Perl warnings report the sanitized template source and exact physical line.
- Templates without a source report `unknown`.
- Each run of carriage returns or newlines in a source label becomes one space, each double quote becomes an apostrophe, and every other ASCII control character becomes `?`; ordinary Unix paths, including spaces, remain unchanged.
- Warning strings ending in a newline retain native Perl behavior and do not gain a location.
- Repeated compilation of the same content and source remains cacheable; identical content under different sources must not share a source-bearing coderef.
- Errors from real module or helper files and render-stack decoration remain unchanged.
- A full per-block source map is out of scope unless these targeted repairs cannot satisfy the regression matrix.

## File Structure

- Create `t/diagnostic_lines.t`: table-driven source/line regression coverage for compilation, rendering, warnings, comments, smart lines, wrapper setup, cache reuse, and existing guard cases.
- Modify `lib/Template/EmbeddedPerl/Utils.pm`: centralize safe diagnostic source labels and recognize source-named template diagnostics.
- Modify `lib/Template/EmbeddedPerl.pm`: bind generated code to the template source, make cache identity source-aware, preserve repeated comment newlines, and retain consumed smart-line newlines as non-output sentinels.
- Keep existing tests unchanged; they remain output and integration regression coverage.

---

### Task 1: Bind Generated Diagnostics To The Template Source

**Files:**
- Create: `t/diagnostic_lines.t`
- Modify: `lib/Template/EmbeddedPerl/Utils.pm:8-17,58-91`
- Modify: `lib/Template/EmbeddedPerl.pm:15,335-392,684-733`
- Include: `docs/superpowers/plans/2026-07-14-template-diagnostic-line-mapping.md`

**Interfaces:**
- Produces: `Template::EmbeddedPerl::Utils::diagnostic_source_label($source) -> $safe_label`.
- Changes internal call: `Template::EmbeddedPerl->compiled($generated_perl, $source) -> $wrapper_perl`.
- Keeps public `from_string`, `compile`, `compiled`, and rendering APIs compatible.

- [ ] **Step 1: Create focused diagnostic helpers and failing source tests**

Create `t/diagnostic_lines.t` with this initial content:

```perl
use strict;
use warnings;

use Test::Most;
use Template::EmbeddedPerl;

sub compile_failure {
    my ($engine, $template, $source) = @_;
    my $error;
    eval { $engine->from_string($template, source => $source); 1 }
        or $error = $@;
    return $error;
}

sub runtime_failure {
    my ($engine, $template, $source) = @_;
    my $compiled = $engine->from_string($template, source => $source);
    my $error;
    eval { $compiled->render; 1 } or $error = $@;
    return $error;
}

sub warning_message {
    my ($engine, $template, $source) = @_;
    my @warnings;
    {
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        $engine->from_string($template, source => $source)->render;
    }
    return join '', @warnings;
}

sub reports_location {
    my ($message, $source, $line, $description) = @_;
    like(
        $message,
        qr/\bat \Q$source\E line $line(?:\.|\n)/,
        $description,
    );
}

reports_location(
    compile_failure(
        Template::EmbeddedPerl->new,
        "head\n<%= \$missing %>\n",
        'pages/compile.epl',
    ),
    'pages/compile.epl',
    2,
    'a compile error reports its template source and line',
);

reports_location(
    warning_message(
        Template::EmbeddedPerl->new,
        "head\n<% warn 'warning' %>\n",
        'pages/warning with spaces.epl',
    ),
    'pages/warning with spaces.epl',
    2,
    'a native warning reports its template source and line',
);

reports_location(
    runtime_failure(
        Template::EmbeddedPerl->new(
            preamble => "my \$first = 1;\nmy \$second = 2;",
        ),
        "head\n<% die 'preamble failure' %>\n",
        'pages/preamble.epl',
    ),
    'pages/preamble.epl',
    2,
    'multiline preamble code does not shift template diagnostics',
);

reports_location(
    runtime_failure(
        Template::EmbeddedPerl->new(
            prepend => "my \$first = 1;\nmy \$second = 2;",
        ),
        "head\n<% die 'prepend failure' %>\n",
        'pages/prepend.epl',
    ),
    'pages/prepend.epl',
    2,
    'multiline prepend code does not shift template diagnostics',
);

my $cached = Template::EmbeddedPerl->new(use_cache => 1);
my $cached_template = "<% warn 'cached warning' %>\n";
for my $source ('pages/cache-first.epl', 'pages/cache-second.epl') {
    reports_location(
        warning_message($cached, $cached_template, $source),
        $source,
        1,
        "a cached coderef reports $source",
    );
}

my $cached_first = $cached->from_string(
    $cached_template,
    source => 'pages/cache-first.epl',
);
my $cached_first_again = $cached->from_string(
    $cached_template,
    source => 'pages/cache-first.epl',
);
my $cached_second = $cached->from_string(
    $cached_template,
    source => 'pages/cache-second.epl',
);
is(
    $cached_first->{code},
    $cached_first_again->{code},
    'identical content and source reuse the cached coderef',
);
isnt(
    $cached_first->{code},
    $cached_second->{code},
    'identical content under different sources uses distinct coderefs',
);

my $unsafe_source = "pages/\tbad\"\nname.epl";
reports_location(
    warning_message(
        Template::EmbeddedPerl->new,
        "<% warn 'safe source' %>\n",
        $unsafe_source,
    ),
    "pages/?bad' name.epl",
    1,
    'unsafe line-directive characters are normalized deterministically',
);

is(
    warning_message(
        Template::EmbeddedPerl->new,
        '<% warn "manual\\n" %>',
        'pages/manual-warning.epl',
    ),
    "manual\n",
    'a warning ending in a newline retains native no-location behavior',
);

done_testing;
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/diagnostic_lines.t
```

Expected: FAIL the warning source, multiline `preamble`, multiline `prepend`,
both cached source assertions, different-source coderef isolation, and the
unsafe-source assertion. The baseline compile assertion, same-source cache
reuse, and newline-terminated warning assertion pass.

- [ ] **Step 3: Add deterministic diagnostic source labels**

Add `diagnostic_source_label` to `@EXPORT_OK` in `lib/Template/EmbeddedPerl/Utils.pm` and define it before `generate_error_message`:

```perl
sub diagnostic_source_label {
  my ($source) = @_;
  my $label = defined($source) && length("$source") ? "$source" : 'unknown';
  $label =~ s/(?:\r\n?|\n)+/ /g;
  $label =~ tr/"/'/;
  $label =~ s/[\x00-\x1f\x7f]/?/g;
  return $label;
}
```

Update `generate_error_message` to normalize once and recognize both legacy eval filenames and the line-directive filename:

```perl
sub generate_error_message {
  my ($msg, $template, $source) = @_;

  warn "RAW MESSAGE: [$msg]" if $ENV{DEBUG_TEMPLATE_EMBEDDED_PERL};

  return $msg if _has_render_stack($msg);

  $source = diagnostic_source_label($source);

  my @files;
  push @files, [$1, $2, $3, $msg] while $msg =~ /^(.+?) at\s+(.+?)\s+line\s+(\d+)/gm;

  return $msg unless @files;

  my $text = '';
  foreach my $file (@files) {
    my ($message, $file_name, $line, $extra) = @$file;
    my $is_template_file = $file_name =~ /\A\(eval \d+\)\z/
      || $file_name eq $source;
    if (!$is_template_file) {
      $text .= $extra;
      next;
    }
    $text .= "$message at $source line $line\n\n";

    $line--;
    my $start = $line - 1 >= 0 ? $line - 1 : 0;
    my $end = $line + 1 < scalar(@$template) ? $line + 1 : scalar(@$template) - 1;
    for my $i ($start .. $end) {
      $text .= "@{[ $i + 1 ]}: $template->[$i]\n";
    }
    $text .= "\n";
  }

  return length($text) ? "$text\n" : $msg;
}
```

- [ ] **Step 4: Bind compiled code and cache identity to the diagnostic source**

Import the helper in `lib/Template/EmbeddedPerl.pm`:

```perl
use Template::EmbeddedPerl::Utils qw(
  diagnostic_source_label
  normalize_linefeeds
  generate_error_message
);
```

In `from_string`, compute the label after constructing `$self`, and include it in the cache digest:

```perl
my $diagnostic_source = diagnostic_source_label($source);

my $digest;
if ($self->{use_cache}) {
  $self->{compiled_cache} ||= {};
  $digest = Digest::MD5::md5_hex(
    $template,
    "\0template-source\0",
    $diagnostic_source,
  );
```

Pass the source through `compile` into `compiled`:

```perl
$compiled = $self->compiled($compiled, $source);
```

Change `compiled` to reset the line and filename after wrapper setup:

```perl
sub compiled {
  my ($self, $compiled, $source) = @_;
  my $diagnostic_source = diagnostic_source_label($source);
  my $wrapper = "package @{[ $self->{sandbox_ns} ]}; ";
  $wrapper .= "use strict; use warnings; use utf8; @{[ $self->{preamble} ]}; ";
  $wrapper .= "sub { my \$__context = shift; my \$_O = ''; my \$self = \$__context->view; @{[ $self->{prepend} ]};\n";
  $wrapper .= qq{#line 1 "$diagnostic_source"\n};
  $wrapper .= "${compiled}; return \$_O; };";
  return $wrapper;
}
```

- [ ] **Step 5: Run focused and existing cache/error tests GREEN**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/diagnostic_lines.t t/regressions.t t/composition_errors.t t/template_lookup.t
```

Expected: PASS. Native warning assertions show page names, wrapper setup no longer shifts lines, both cache sources remain distinct, and existing decorated errors/cache metadata remain correct.

- [ ] **Step 6: Commit Task 1**

```bash
git add t/diagnostic_lines.t lib/Template/EmbeddedPerl.pm lib/Template/EmbeddedPerl/Utils.pm docs/superpowers/plans/2026-07-14-template-diagnostic-line-mapping.md
git commit -m "fix: bind diagnostics to template sources"
```

---

### Task 2: Preserve Repeated Continued-Comment Lines

**Files:**
- Modify: `t/diagnostic_lines.t`
- Modify: `lib/Template/EmbeddedPerl.pm:707-713`

**Interfaces:**
- Consumes: `compile_failure`, `runtime_failure`, `warning_message`, and `reports_location` from Task 1.
- Produces: one generated Perl newline for every removed escaped-newline sentinel, with unchanged rendered output.

- [ ] **Step 1: Add the continued-comment regression matrix**

Insert before `done_testing` in `t/diagnostic_lines.t`:

```perl
my %diagnostic_runner = (
    compile => \&compile_failure,
    runtime => \&runtime_failure,
    warning => \&warning_message,
);

for my $case (
    {
        name => 'one continued comment',
        kind => 'runtime',
        template => "# one\\\n<% die 'one comment' %>\n",
        line => 2,
    },
    {
        name => 'two continued comments before a compile error',
        kind => 'compile',
        template => "# one\\\n# two\\\n<%= \$missing %>\n",
        line => 3,
    },
    {
        name => 'three continued comments before a runtime error',
        kind => 'runtime',
        template => "# one\\\n# two\\\n# three\\\n<% die 'three comments' %>\n",
        line => 4,
    },
    {
        name => 'continued comments before a warning',
        kind => 'warning',
        template => "# one\\\n# two\\\n<% warn 'comment warning' %>\n",
        line => 3,
    },
    {
        name => 'continued comments in the middle',
        kind => 'runtime',
        template => "head\n# one\\\n# two\\\ntail\n<% die 'middle comments' %>\n",
        line => 5,
    },
) {
    my $source = "comments-$case->{kind}.epl";
    reports_location(
        $diagnostic_runner{$case->{kind}}->(
            Template::EmbeddedPerl->new,
            $case->{template},
            $source,
        ),
        $source,
        $case->{line},
        $case->{name},
    );
}

for my $case (
    {
        name => 'custom comment marker',
        engine => Template::EmbeddedPerl->new(comment_mark => '*'),
        template => "* one\\\n* two\\\n<% die 'custom comments' %>\n",
        source => 'custom-comments.epl',
        line => 3,
    },
    {
        name => 'CRLF continued comments',
        engine => Template::EmbeddedPerl->new,
        template => "# one\\\r\n# two\\\r\n<% die 'crlf comments' %>\r\n",
        source => 'crlf-comments.epl',
        line => 3,
    },
) {
    reports_location(
        runtime_failure($case->{engine}, $case->{template}, $case->{source}),
        $case->{source},
        $case->{line},
        $case->{name},
    );
}

reports_location(
    runtime_failure(
        Template::EmbeddedPerl->new,
        "# ordinary\n  # indented\nvisible\n<% die 'ordinary comments' %>\n",
        'ordinary-comments.epl',
    ),
    'ordinary-comments.epl',
    4,
    'ordinary comments retain their existing correct mapping',
);

reports_location(
    runtime_failure(
        Template::EmbeddedPerl->new,
        "\\# visible comment marker\ntext\n<% die 'escaped comment' %>\n",
        'escaped-comment.epl',
    ),
    'escaped-comment.epl',
    3,
    'an escaped comment marker retains its existing correct mapping',
);

reports_location(
    runtime_failure(
        Template::EmbeddedPerl->new,
        "first\\\nsecond\\\n<% die 'escaped output lines' %>\n",
        'escaped-output-lines.epl',
    ),
    'escaped-output-lines.epl',
    3,
    'ordinary escaped output newlines retain their existing correct mapping',
);

is(
    Template::EmbeddedPerl->from_string(
        "# one\\\n# two\\\nbody\n",
        source => 'comment-output.epl',
    )->render,
    "body\n",
    'continued comment repair does not restore removed output newlines',
);
is(
    Template::EmbeddedPerl->from_string(
        "first\\\nsecond\\\n",
        source => 'escaped-output.epl',
    )->render,
    'firstsecond',
    'ordinary escaped output newlines remain suppressed',
);
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/diagnostic_lines.t
```

Expected: FAIL every case containing two or more continued comments. The one-comment, ordinary-comment, escaped-comment, and output assertions pass.

- [ ] **Step 3: Emit the complete escaped-newline counts**

Replace the boolean newline interpolation in the text branch of `compile` with integer repetition:

```perl
my $escaped_newline_start = $content =~ s/^\\\n//mg;
my $escaped_newline_end = $content =~ s/\\\n$//mg;

$content =~ s/^\\\\/\\/mg;
$compiled .= ("\n" x $escaped_newline_start)
  . ' $_O .= "' . quotemeta($content) . '";'
  . ("\n" x $escaped_newline_end);
```

- [ ] **Step 4: Run focused comment and output tests GREEN**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/diagnostic_lines.t t/basic.t t/newline_trim.t
```

Expected: PASS. Exact diagnostic lines are restored and all existing comment/escaped-newline output remains byte-for-byte unchanged.

- [ ] **Step 5: Commit Task 2**

```bash
git add t/diagnostic_lines.t lib/Template/EmbeddedPerl.pm
git commit -m "fix: preserve continued comment source lines"
```

---

### Task 3: Preserve Smart-Line Source Lines And Complete The Guard Matrix

**Files:**
- Modify: `t/diagnostic_lines.t`
- Modify: `lib/Template/EmbeddedPerl.pm:566-581`

**Interfaces:**
- Consumes: the diagnostic helpers and source-bearing generated wrapper from Tasks 1-2.
- Produces: smart-line rewrites that consume directive output while retaining one generated source newline per physical newline.

- [ ] **Step 1: Add failing smart-line cases and passing mapping guards**

Insert before `done_testing` in `t/diagnostic_lines.t`:

```perl
for my $case (
    {
        name => 'consecutive smart code lines',
        kind => 'runtime',
        template => "% my \$first = 1\n% my \$second = 2\n% die 'smart runtime'\n",
        line => 3,
    },
    {
        name => 'smart expression compile error',
        kind => 'compile',
        template => "% my \$first = 1\n%= \$missing\n",
        line => 2,
    },
    {
        name => 'consecutive smart warning',
        kind => 'warning',
        template => "% my \$first = 1\n% my \$second = 2\n% warn 'smart warning'\n",
        line => 3,
    },
    {
        name => 'smart line after an ordinary comment',
        kind => 'runtime',
        template => "% my \$first = 1\n# hidden\n% die 'smart comment'\n",
        line => 3,
    },
    {
        name => 'smart line after continued comments',
        kind => 'runtime',
        template => "% my \$first = 1\n# one\\\n# two\\\n% die 'smart continued comments'\n",
        line => 4,
    },
) {
    my $source = "smart-$case->{kind}.epl";
    reports_location(
        $diagnostic_runner{$case->{kind}}->(
            Template::EmbeddedPerl->new(smart_lines => 1),
            $case->{template},
            $source,
        ),
        $source,
        $case->{line},
        $case->{name},
    );
}

my $custom_smart = Template::EmbeddedPerl->new(
    open_tag => '[[',
    close_tag => ']]',
    expr_marker => '?',
    line_start => '++',
    smart_lines => 1,
);
reports_location(
    warning_message(
        $custom_smart,
        "++ my \$first = 1\n++ my \$second = 2\n++ warn 'custom smart warning'\n",
        'custom-smart.epl',
    ),
    'custom-smart.epl',
    3,
    'custom smart markers preserve physical lines',
);

reports_location(
    runtime_failure(
        Template::EmbeddedPerl->new(smart_lines => 1),
        "% my \$first = 1\r\n% my \$second = 2\r\n% die 'smart crlf'\r\n",
        'smart-crlf.epl',
    ),
    'smart-crlf.epl',
    3,
    'smart CRLF input reports its normalized physical line',
);

for my $guard (
    {
        name => 'multiline Perl block',
        engine => Template::EmbeddedPerl->new,
        template => "head\n<%\nmy \$value = 1;\ndie 'multiline';\n%>\n",
        source => 'multiline.epl',
        line => 4,
    },
    {
        name => 'trim-close tag',
        engine => Template::EmbeddedPerl->new,
        template => "<% my \$value = 1; -%>\n<% die 'trimmed' %>\n",
        source => 'trimmed.epl',
        line => 2,
    },
    {
        name => 'interpolation',
        engine => Template::EmbeddedPerl->new(interpolation => 1),
        template => "<% my \$value = 'ok' %>\n\$value\n<% die 'interpolation' %>\n",
        source => 'interpolation.epl',
        line => 3,
    },
    {
        name => 'named args rewrite',
        engine => Template::EmbeddedPerl->new(smart_lines => 1),
        template => "# heading\n% args \$name = 'Ada'\n<% die 'args' %>\n",
        source => 'args-lines.epl',
        line => 3,
    },
) {
    reports_location(
        runtime_failure($guard->{engine}, $guard->{template}, $guard->{source}),
        $guard->{source},
        $guard->{line},
        "$guard->{name} retains its existing correct mapping",
    );
}

my $smart_output = Template::EmbeddedPerl->new(smart_lines => 1);
is(
    $smart_output->from_string(
        "% my \$show = 1\n% if (\$show) {\n  <p>Shown</p>\n% }\n",
        source => 'smart-output.epl',
    )->render,
    "  <p>Shown</p>\n",
    'smart-line source sentinels do not restore directive output newlines',
);
is(
    $smart_output->from_string("%= uc 'ok'\n", source => 'smart-expression.epl')->render,
    'OK',
    'smart expression output still consumes its trailing newline',
);
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/diagnostic_lines.t
```

Expected: FAIL the consecutive smart, smart/comment, custom smart, and smart CRLF line assertions. The multiline block, trim, interpolation, args, and rendered-output guards pass.

- [ ] **Step 3: Retain smart physical newlines as escaped sentinels**

Replace the two `smart_lines` substitutions in `parse_template` with:

```perl
$template =~ s{
    ^[\t ]*\Q${line_start}${expr_marker}\E(.*?)(\n|\z)
}{
    $open_tag . $expr_marker . $1 . $close_tag
      . (length($2) ? "\\\n" : '')
}mgex;
$template =~ s{
    ^[\t ]*(?!\Q${close_tag}\E[\t ]*$)\Q${line_start}\E(.*?)(\n|\z)
}{
    $open_tag . $1 . $close_tag
      . (length($2) ? "\\\n" : '')
}mgex;
```

- [ ] **Step 4: Run focused diagnostic, smart-line, argument, and trim tests GREEN**

Run:

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/diagnostic_lines.t t/smart_lines.t t/args.t t/newline_trim.t
```

Expected: PASS. Every smart diagnostic reports the physical template line while all smart-line output remains unchanged.

- [ ] **Step 5: Commit Task 3**

```bash
git add t/diagnostic_lines.t lib/Template/EmbeddedPerl.pm
git commit -m "fix: preserve smart line diagnostics"
```

---

### Task 4: Complete Integration Verification

**Files:**
- Verify only; no planned file changes.

**Interfaces:**
- Consumes: the completed diagnostic mapping and all existing template APIs.
- Produces: evidence that exact diagnostics improved without output, composition, cache, or typed-view regressions.

- [ ] **Step 1: Run the focused diagnostic suite verbosely**

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/diagnostic_lines.t
```

Expected: every compile, runtime, warning, comment, smart-line, wrapper, cache, and guard assertion passes.

- [ ] **Step 2: Run the highest-risk existing suites**

```bash
perlbrew exec --with perl-5.40.0@default prove -lv t/basic.t t/smart_lines.t t/newline_trim.t t/args.t t/regressions.t t/composition_errors.t t/template_lookup.t t/typed_view.t
```

Expected: PASS with unchanged rendered-output and composition behavior.

- [ ] **Step 3: Run the complete suite**

```bash
perlbrew exec --with perl-5.40.0@default prove -lr t
```

Expected: all test files and assertions pass.

- [ ] **Step 4: Check POD and the complete feature diff**

```bash
perlbrew exec --with perl-5.40.0@default podchecker lib/Template/EmbeddedPerl.pm
git diff --check f74912e..HEAD
git status --short --branch
```

Expected: POD syntax is valid, with only the repository's pre-existing whitespace-only paragraph warning if still present; the diff check has no output; the working tree is clean.
