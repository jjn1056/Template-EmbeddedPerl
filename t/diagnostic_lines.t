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

my $unsafe_args_error = compile_failure(
    Template::EmbeddedPerl->new,
    "% args \@items\n",
    $unsafe_source,
);
is(
    $unsafe_args_error,
    "args directive accepts only scalar arguments at pages/?bad' name.epl line 1\n",
    'an args rewrite error reports its sanitized source and line',
);
unlike(
    $unsafe_args_error,
    qr/\Q$unsafe_source\E/,
    'an args rewrite error does not leak the raw unsafe source',
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
