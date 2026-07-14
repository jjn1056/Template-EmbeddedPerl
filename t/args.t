use Test::Most;
use Template::EmbeddedPerl;
use Template::EmbeddedPerl::Arguments;

my $engine = Template::EmbeddedPerl->new(smart_lines => 1);

my $compiled = $engine->from_string(<<'EPL');
% args $name, $greeting = 'Hello'
<%= $greeting %>, <%= $name %>!
EPL

is(
    $compiled->render(name => 'Jane'),
    "Hello, Jane!\n",
    'expression default is used',
);
is(
    $compiled->render(name => 'Jane', greeting => 'Hi'),
    "Hi, Jane!\n",
    'default is overridden',
);

my $ordered_default = $engine->from_string(<<'EPL');
% args $name, $label = "Hello, $name"
<%= $label %> (<%= scalar @_ %>)
EPL

is(
    $ordered_default->render(name => 'Jane'),
    "Hello, Jane (2)\n",
    'expression defaults see earlier arguments and the original argument list',
);

my $legacy_engine = Template::EmbeddedPerl->new;
is(
    $legacy_engine->from_string("% args \$name\n<%= \$name %>\n")->render(name => 'Jane'),
    "Jane\n",
    'args directive does not require smart lines',
);

my ($rewritten, $has_args) = Template::EmbeddedPerl::Arguments->rewrite(
    "% args \$name\n<%= \$name %>\n",
);
ok($has_args, 'rewrite reports an args directive');
is(
    $rewritten =~ tr/\n//,
    2,
    'rewrite preserves the template newline count',
);

my ($unchanged, $has_no_args) = Template::EmbeddedPerl::Arguments->rewrite("plain text\n");
is($unchanged, "plain text\n", 'rewrite leaves templates without args unchanged');
ok(!$has_no_args, 'rewrite reports when no args directive exists');

my $factory_calls = 0;
my $lazy_engine = Template::EmbeddedPerl->new(
    smart_lines => 1,
    helpers => {
        record_factory_call => sub { $factory_calls++ },
    },
);
my $lazy = $lazy_engine->from_string(<<'EPL');
% args $items, $title = sub {
%   record_factory_call();
%   my $count = @$items;
%   return $count == 1 ? 'One item' : "$count items";
% }
<%= defined $title ? $title : '' %>
EPL

is($lazy->render(items => [1, 2]), "2 items\n", 'lazy factory can use an earlier argument');
is($factory_calls, 1, 'lazy factory runs once when the argument is absent');
is($lazy->render(items => [], title => undef), "\n", 'explicit undef does not use default');
is($factory_calls, 1, 'lazy factory does not run for explicit undef');
is($lazy->render(items => [1], title => 'Custom'), "Custom\n", 'provided value overrides lazy factory');
is($factory_calls, 1, 'lazy factory does not run for a provided value');

throws_ok { $compiled->render } qr/Missing required template argument 'name'/;
throws_ok {
    $compiled->render(name => 'Jane', zebra => 1, alpha => 2);
} qr/Unknown template argument 'alpha'/;
throws_ok {
    $compiled->render(name => 'Jane', name => 'John');
} qr/Duplicate template argument 'name'/;
throws_ok {
    $compiled->render(name => 'Jane', 'odd');
} qr/Odd template argument list/;

my $multiline = $engine->from_string(<<'EPL');
# argument declaration follows a template comment

% args
%   $name,
%   $punctuation = (
%       1 ? '!' : '?'
%   )
<%= $name %><%= $punctuation %>
EPL

is(
    $multiline->render(name => 'Jane'),
    "\n\nJane!\n",
    'comments and blank lines may precede a multiline declaration',
);

throws_ok {
    $engine->from_string("text\n% args \$name\n");
} qr/args must be the first executable directive/;

throws_ok {
    $engine->from_string("% my \$before = 1\n% args \$name\n");
} qr/args must be the first executable directive/;

throws_ok {
    $engine->from_string("% args \$name\n% args \$other\n");
} qr/args directive may only appear once/;

for my $case (
    [q{% args @items}, qr/scalar argument/],
    [q{% args $name =}, qr/default expression/],
    [q{% args $name,}, qr/incomplete args directive/],
    [q{% args $name, $name}, qr/Duplicate args declaration 'name'/],
) {
    throws_ok { $engine->from_string("$case->[0]\n") } $case->[1];
}

my $source_error = $engine->from_string(<<'EPL', source => 'views/arguments.epl');
# heading
% args $name
<%= $name %>
EPL

throws_ok {
    $source_error->render;
} qr/Missing required template argument 'name' at views\/arguments\.epl line 2/;

my $unknown_source = $engine->from_string(<<'EPL', source => 'views/unknown-argument.epl');
% args $name, $greeting = 'Hello'
<%= $greeting %>, <%= $name %>!
EPL

throws_ok {
    $unknown_source->render(name => 'Jane', extra => 1);
} qr/Unknown template argument 'extra' at views\/unknown-argument\.epl line 1/;

my $bad_default = $engine->from_string(<<'EPL', source => 'views/bad-default.epl');
% args $name = (
%   missing_function()
% )
<%= $name %>
EPL

throws_ok {
    $bad_default->render;
} qr/at views\/bad-default\.epl line 2/;

done_testing;
