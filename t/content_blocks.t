use Test::Most;
use File::Spec;
use Template::EmbeddedPerl;

my $template_directory = File::Spec->catdir(qw(t templates composition));
my $engine = Template::EmbeddedPerl->new(
    directories => [$template_directory],
    smart_lines => 1,
    auto_escape => 1,
    helpers => {
        inspect_safe => sub {
            my ($engine, $value) = @_;
            return Template::EmbeddedPerl::SafeString::is_safe($value)
                ? 'safe'
                : 'unsafe';
        },
    },
);

my $append = $engine->from_string(<<'EPL', source => 'pages/content-append.epl');
% layout 'layouts/slots'
% content_for css => sub { raw '<link href="one.css">' }
% content_for css => sub { raw '<link href="two.css">' }
<main>Body</main>
EPL

is(
    $append->render,
    '<css safe="safe"><link href="one.css"><link href="two.css"></css>'
        . "<body><main>Body</main>\n</body>"
        . '<js safe="safe"></js><has-css>yes</has-css>',
    'content_for appends safe captured output in render order',
);

my $replace = $engine->from_string(<<'EPL', source => 'pages/content-replace.epl');
% layout 'layouts/slots'
% content_for css => sub { raw '<link href="one.css">' }
% content_for css => sub { raw '<link href="two.css">' }
% content_replace css => sub { raw '<link href="replacement.css">' }
<main>Body</main>
EPL

is(
    $replace->render,
    '<css safe="safe"><link href="replacement.css"></css>'
        . "<body><main>Body</main>\n</body>"
        . '<js safe="safe"></js><has-css>yes</has-css>',
    'content_replace discards earlier named content',
);

my $nested_partial = $engine->from_string(
    q{<% layout 'layouts/slots'; partial 'slots/contributor'; %><main>Body</main>},
    source => 'pages/content-partial.epl',
);
is(
    $nested_partial->render,
    '<css safe="safe"><link href="nested.css"></css>'
        . '<body><main>Body</main></body>'
        . '<js safe="safe"></js><has-css>yes</has-css>',
    'a partial contribution reaches the outer layout',
);

my $has_content = $engine->from_string(
    q{<%= has_content('css') ? 'yes' : 'no' %><% content_for css => sub { '' }; %><%= has_content('css') ? 'yes' : 'no' %><% content_for css => sub { raw 'value' }; %><%= has_content('css') ? 'yes' : 'no' %>},
    source => 'pages/has-content.epl',
);
is($has_content->render, 'nonoyes', 'has_content reports only nonempty named content');

my $callback_calls = 0;
my $callback_once = $engine->from_string(
    q{<% my $calls = shift; content_for css => sub { ++$$calls; raw '<link href="once.css">' }; %><%= yield 'css' %>},
    source => 'pages/callback-once.epl',
);
is($callback_once->render(\$callback_calls), '<link href="once.css">', 'content_for renders captured output');
is($callback_calls, 1, 'content_for invokes its callback exactly once');

my $replace_calls = 0;
my $replace_once = $engine->from_string(
    q{<% my $calls = shift; content_replace css => sub { ++$$calls; raw '<link href="replace-once.css">' }; %><%= yield 'css' %>},
    source => 'pages/replace-once.epl',
);
is($replace_once->render(\$replace_calls), '<link href="replace-once.css">', 'content_replace renders captured output');
is($replace_calls, 1, 'content_replace invokes its callback exactly once');

my $invalid_name = $engine->from_string(
    q{<%= content_for undef, sub { '' } %>},
    source => 'pages/invalid-content-name.epl',
);
throws_ok { $invalid_name->render } qr/Invalid content_for name/,
    'content_for requires a defined string name';

my $invalid_callback = $engine->from_string(
    q{<%= content_replace 'css', 'not a callback' %>},
    source => 'pages/invalid-content-callback.epl',
);
throws_ok { $invalid_callback->render } qr/Invalid content_replace callback/,
    'content_replace requires a code callback';

my $first_frame = $engine->from_string(
    q{<% content_for css => sub { raw '<link href="first.css">' }; %><%= yield 'css' %>},
    source => 'pages/first-frame.epl',
);
my $second_frame = $engine->from_string(
    q{<%= yield 'css' %><%= has_content('css') ? 'yes' : 'no' %>},
    source => 'pages/second-frame.epl',
);
is($first_frame->render, '<link href="first.css">', 'first top-level render stores named content');
is($second_frame->render, 'no', 'named content does not leak between top-level frames');

done_testing;
