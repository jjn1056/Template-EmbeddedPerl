use v5.40;
use Test::Most;
use File::Path 'make_path';
use File::Spec;
use File::Temp 'tempdir';
use Scalar::Util 'refaddr';
use Template::EmbeddedPerl;

{
    package Local::CompositionErrors::View::HTML::Self;

    sub new { bless {}, $_[0] }
}

{
    package Local::CompositionErrors::View::HTML::Explodes;

    sub new { bless {}, $_[0] }
}

sub write_fixture ($root, $identifier, $content) {
    my @parts = split m{/}, "$identifier.epl";
    my $file = File::Spec->catfile($root, @parts);
    my (undef, $directory) = File::Spec->splitpath($file);
    make_path($directory);
    open my $handle, '>', $file or die "Cannot write $file: $!";
    print {$handle} $content;
    close $handle or die "Cannot close $file: $!";
    return $file;
}

sub capture_failure ($callback) {
    my $error;
    local $SIG{ALRM} = sub { die "render timed out\n" };
    local $SIG{__WARN__} = sub {
        die "uncontrolled recursion: $_[0]" if $_[0] =~ /Deep recursion/;
        warn $_[0];
    };
    alarm 3;
    eval { $callback->(); 1 } or $error = $@;
    alarm 0;
    return $error;
}

sub stack_section ($error) {
    my ($stack) = $error =~ /^(Render stack:\n.*)\z/ms;
    return $stack;
}

sub assert_single_stack ($error, $expected, $description) {
    is(scalar(() = $error =~ /^Render stack:$/mg), 1, "$description has one render stack");
    is(stack_section($error), $expected, "$description has the ordered render stack");
}

sub assert_frame_clean ($frame, $description) {
    is_deeply($frame->render_stack, [], "$description clears the render stack");
    is($frame->default_body, '', "$description clears the default body");
    is($frame->content('css'), '', "$description clears named CSS content");
    is($frame->content('js'), '', "$description clears named JavaScript content");
}

my $directory = tempdir(CLEANUP => 1);
my $partial_self_source = write_fixture(
    $directory,
    'partials/self',
    "%= partial 'partials/self'\n",
);
my $layout_self_source = write_fixture(
    $directory,
    'layouts/self',
    "% layout 'layouts/self'\nbody\n",
);
my $view_self_source = write_fixture(
    $directory,
    'html/self',
    "%= view \$self\n",
);
my $runtime_partial_source = write_fixture(
    $directory,
    'partials/runtime',
    "% args \$child\n%= view \$child\n",
);
my $runtime_view_source = write_fixture(
    $directory,
    'html/explodes',
    "before\n% die \"nested runtime failed\"\n",
);
my $failing_layout_source = write_fixture(
    $directory,
    'layouts/fails',
    "layout before\n% die \"layout runtime failed\"\n",
);

my $last_probe_context;
my $engine = Template::EmbeddedPerl->new(
    directories => [$directory],
    view_namespace => 'Local::CompositionErrors::View',
    smart_lines => 1,
    preamble => 'use v5.40;',
    helpers => {
        state_probe => sub {
            my $context = Template::EmbeddedPerl->_current_render_context('state_probe');
            $last_probe_context = $context;
            return join '|',
                scalar(@{$context->frame->render_stack}),
                $context->frame->default_body,
                $context->frame->content('css'),
                $context->frame->content('js');
        },
    },
);

my $known_good = $engine->from_string(
    '<%= state_probe %>',
    source => 'known-good.epl',
    identifier => 'known-good',
);

sub assert_engine_reusable ($failed_frame, $description) {
    is($known_good->render, '1|||', "$description leaves the engine reusable");
    isnt(
        refaddr($last_probe_context->frame),
        refaddr($failed_frame),
        "$description uses a fresh top-level frame",
    );
    my $outside_error = capture_failure(sub {
        Template::EmbeddedPerl->_current_render_context('outside_probe');
    });
    like(
        $outside_error,
        qr/Template helper 'outside_probe' called outside render context/,
        "$description restores ACTIVE_RENDERER",
    );
}

my $partial_root_source = File::Spec->catfile($directory, qw(roots partial-self.epl));
my $partial_root = $engine->from_string(
    "%= partial 'partials/self'\n",
    source => $partial_root_source,
    identifier => 'roots/partial-self',
);
my $partial_context = $engine->_new_render_context(source => $partial_root_source);
$partial_context->frame->append_content('css', 'stale partial css');
my $partial_error = capture_failure(sub {
    $partial_root->_render_with_context(
        $partial_context,
        {
            kind => 'root',
            identifier => 'roots/partial-self',
            source => $partial_root_source,
        },
    );
});
like(
    $partial_error,
    qr/Render cycle detected: partial partials\/self -> partial partials\/self/,
    'a partial self-cycle is rejected before uncontrolled recursion',
);
assert_single_stack(
    $partial_error,
    "Render stack:\n"
        . "  root roots/partial-self ($partial_root_source)\n"
        . "  partial partials/self ($partial_self_source)\n",
    'partial cycle',
);
assert_frame_clean($partial_context->frame, 'partial cycle failure');
assert_engine_reusable($partial_context->frame, 'partial cycle failure');

my $layout_context = $engine->_new_render_context(source => $layout_self_source);
$layout_context->frame->append_content('js', 'stale layout js');
my $layout_error = capture_failure(sub {
    $engine->from_file('layouts/self')->_render_with_context(
        $layout_context,
        {
            kind => 'root',
            identifier => 'layouts/self',
            source => $layout_self_source,
        },
    );
});
like(
    $layout_error,
    qr/Render cycle detected: layout layouts\/self -> layout layouts\/self/,
    'a layout self-cycle is rejected during deferred layout application',
);
assert_single_stack(
    $layout_error,
    "Render stack:\n"
        . "  root layouts/self ($layout_self_source)\n"
        . "  layout layouts/self ($layout_self_source)\n",
    'layout cycle',
);
assert_frame_clean($layout_context->frame, 'layout cycle failure');
assert_engine_reusable($layout_context->frame, 'layout cycle failure');

my $self_view = Local::CompositionErrors::View::HTML::Self->new;
my $view_context = $engine->_new_render_context(
    view => $self_view,
    root_view => $self_view,
    source => $view_self_source,
);
$view_context->frame->append_content('css', 'stale view css');
my $view_error = capture_failure(sub {
    $view_context->render_view_object($self_view);
});
like(
    $view_error,
    qr/Render cycle detected: view Local::CompositionErrors::View::HTML::Self -> view Local::CompositionErrors::View::HTML::Self/,
    'a repeated active typed view is rejected before uncontrolled recursion',
);
assert_single_stack(
    $view_error,
    "Render stack:\n"
        . "  root Local::CompositionErrors::View::HTML::Self ($view_self_source)\n"
        . "  view Local::CompositionErrors::View::HTML::Self ($view_self_source)\n",
    'typed view cycle',
);
assert_frame_clean($view_context->frame, 'typed view cycle failure');
assert_engine_reusable($view_context->frame, 'typed view cycle failure');

my $runtime_root_source = File::Spec->catfile($directory, qw(roots runtime.epl));
my $runtime_root = $engine->from_string(
    "%= partial 'partials/runtime', child => \$_[0]\n",
    source => $runtime_root_source,
    identifier => 'roots/runtime',
);
my $runtime_context = $engine->_new_render_context(source => $runtime_root_source);
my $exploding_view = Local::CompositionErrors::View::HTML::Explodes->new;
my $runtime_error = capture_failure(sub {
    $runtime_root->_render_with_context(
        $runtime_context,
        {
            kind => 'root',
            identifier => 'roots/runtime',
            source => $runtime_root_source,
        },
        $exploding_view,
    );
});
like($runtime_error, qr/nested runtime failed/, 'nested runtime diagnostics preserve the original message');
like(
    $runtime_error,
    qr/nested runtime failed at \Q$runtime_view_source\E line 2/,
    'nested runtime diagnostics preserve the exact failing source and line',
);
assert_single_stack(
    $runtime_error,
    "Render stack:\n"
        . "  root roots/runtime ($runtime_root_source)\n"
        . "  partial partials/runtime ($runtime_partial_source)\n"
        . "  view Local::CompositionErrors::View::HTML::Explodes ($runtime_view_source)\n",
    'nested runtime failure',
);
assert_frame_clean($runtime_context->frame, 'nested runtime failure');
assert_engine_reusable($runtime_context->frame, 'nested runtime failure');

my $layout_runtime_root_source = File::Spec->catfile($directory, qw(roots layout-runtime.epl));
my $layout_runtime_root = $engine->from_string(
    "% layout 'layouts/fails'\nbody\n",
    source => $layout_runtime_root_source,
    identifier => 'roots/layout-runtime',
);
my $layout_runtime_context = $engine->_new_render_context(source => $layout_runtime_root_source);
my $layout_runtime_error = capture_failure(sub {
    $layout_runtime_root->_render_with_context(
        $layout_runtime_context,
        {
            kind => 'root',
            identifier => 'roots/layout-runtime',
            source => $layout_runtime_root_source,
        },
    );
});
like(
    $layout_runtime_error,
    qr/layout runtime failed at \Q$failing_layout_source\E line 2/,
    'a deferred layout failure preserves its exact source and line',
);
assert_single_stack(
    $layout_runtime_error,
    "Render stack:\n"
        . "  root roots/layout-runtime ($layout_runtime_root_source)\n"
        . "  layout layouts/fails ($failing_layout_source)\n",
    'deferred layout runtime failure',
);
assert_frame_clean($layout_runtime_context->frame, 'deferred layout runtime failure');
assert_engine_reusable($layout_runtime_context->frame, 'deferred layout runtime failure');

my $callback_root_source = File::Spec->catfile($directory, qw(roots callback.epl));
my $callback_root = $engine->from_string(<<'EPL',
% content_for css => sub { raw 'callback css' }
%= view $_[0], sub ($wrapper) {
% content_for js => sub { raw 'callback js' }
% die "wrapper callback failed"
% }
EPL
    source => $callback_root_source,
    identifier => 'roots/callback',
);
my $callback_context = $engine->_new_render_context(source => $callback_root_source);
my $callback_error = capture_failure(sub {
    $callback_root->_render_with_context(
        $callback_context,
        {
            kind => 'root',
            identifier => 'roots/callback',
            source => $callback_root_source,
        },
        $self_view,
    );
});
like($callback_error, qr/wrapper callback failed/, 'a typed wrapper callback failure propagates');
assert_single_stack(
    $callback_error,
    "Render stack:\n"
        . "  root roots/callback ($callback_root_source)\n",
    'typed wrapper callback failure',
);
assert_frame_clean($callback_context->frame, 'typed wrapper callback failure');
assert_engine_reusable($callback_context->frame, 'typed wrapper callback failure');

my $first_success = $engine->from_string(
    q{<% content_for css => sub { raw 'first css' }; %><%= yield 'css' %>},
    source => 'first-success.epl',
    identifier => 'first-success',
);
my $second_success = $engine->from_string(
    q{<%= yield 'css' %><%= has_content('css') ? 'leaked' : 'clean' %>},
    source => 'second-success.epl',
    identifier => 'second-success',
);
is($first_success->render, 'first css', 'the first successful top-level render contributes named content');
is($second_success->render, 'clean', 'named content does not leak between successful top-level renders');

done_testing;
