use strict;
use warnings;

use Cwd qw(getcwd);
use File::Spec;
use IPC::Open3;
use Symbol qw(gensym);
use Test::Most;
use Template::EmbeddedPerl;

my $root = File::Spec->rel2abs('.');
my $untyped_root = File::Spec->catdir($root, qw(examples contacts untyped));
my $untyped_lib = File::Spec->catdir($untyped_root, 'lib');

unshift @INC, $untyped_lib;
require Contacts::Untyped::App;

my $expected_html = <<'HTML';
<!doctype html>
<html>
<head>
<title>Contacts</title>
<meta name="section" content="contacts">
</head>
<body>
<section class="page">
<main>
<h1>CONTACTS</h1>
<p class="badge">2 contacts</p>
<ul>
<li data-root="Contacts" data-parent="Contacts"><strong>&lt;Ada&gt;</strong> ada@example.test</li>
<li data-root="Contacts" data-parent="Contacts"><strong>Grace</strong> grace@example.test</li>
</ul>
</main>
</section>
</body>
</html>
HTML

sub run_script {
    my ($script, $working_directory) = @_;
    my $original_directory = getcwd;

    chdir $working_directory
        or die "Cannot change to $working_directory: $!";

    my $stderr = gensym;
    my ($stdin, $stdout);
    my $pid = open3($stdin, $stdout, $stderr, $^X, $script);
    close $stdin or die "Cannot close stdin for $script: $!";
    chdir $original_directory
        or die "Cannot change back to $original_directory: $!";

    local $/;
    my $output = <$stdout>;
    my $errors = <$stderr>;
    waitpid $pid, 0;

    return ($output // '', $errors // '', $?);
}

my $untyped = Contacts::Untyped::App->new(root => $untyped_root);
is($untyped->heading_calls, 0, 'lazy heading default has not run before rendering');
is($untyped->render, $expected_html, 'untyped Contacts application renders expected HTML');
is($untyped->heading_calls, 1, 'absent heading evaluates the lazy default once');

$untyped->render(heading => 'Directory');
is($untyped->heading_calls, 1, 'explicit heading bypasses the lazy default');

my ($documented_output, $documented_errors, $documented_status) = run_script(
    File::Spec->catfile(qw(examples contacts untyped app.pl)),
    $root,
);
is($documented_status, 0, 'documented untyped command exits successfully');
is($documented_errors, '', 'documented untyped command writes no errors');
is(
    $documented_output,
    $expected_html,
    'documented untyped command renders expected HTML',
);

my ($independent_output, $independent_errors, $independent_status) = run_script(
    File::Spec->catfile($untyped_root, 'app.pl'),
    File::Spec->tmpdir,
);
is($independent_status, 0, 'untyped command exits successfully outside the distribution');
is($independent_errors, '', 'untyped command writes no errors outside the distribution');
is(
    $independent_output,
    $expected_html,
    'untyped command renders expected HTML outside the distribution',
);

my $typed_root = File::Spec->catdir($root, qw(examples contacts typed));
my $typed_lib = File::Spec->catdir($typed_root, 'lib');
unshift @INC, $typed_lib;
require Contacts::Typed::App;

my $typed = Contacts::Typed::App->new(root => $typed_root);
my $typed_html = $typed->render;
is($typed_html, $expected_html, 'typed Contacts refactor preserves exact HTML');
is($typed_html, $untyped->render, 'typed and untyped applications have output parity');

my ($typed_documented_output, $typed_documented_errors, $typed_documented_status) = run_script(
    File::Spec->catfile(qw(examples contacts typed app.pl)),
    $root,
);
is($typed_documented_status, 0, 'documented typed command exits successfully');
is($typed_documented_errors, '', 'documented typed command writes no errors');
is(
    $typed_documented_output,
    $expected_html,
    'typed command-line example renders expected HTML',
);

my ($typed_independent_output, $typed_independent_errors, $typed_independent_status) = run_script(
    File::Spec->catfile($typed_root, 'app.pl'),
    File::Spec->tmpdir,
);
is($typed_independent_status, 0, 'typed command exits successfully outside the distribution');
is($typed_independent_errors, '', 'typed command writes no errors outside the distribution');
is(
    $typed_independent_output,
    $expected_html,
    'typed command renders expected HTML outside the distribution',
);

my $root_view = $typed->root_view;
my ($page_call) = grep {
    $_->{class} eq 'Contacts::Typed::View::HTML::Page'
} @{$typed->factory_calls};
ok($page_call, 'view factory constructs the typed wrapper');
is($page_call->{view}->root, $root_view, 'wrapper receives the typed root');
is($page_call->{view}->parent, $root_view, 'wrapper receives the caller as parent');

my @item_calls = grep {
    $_->{class} eq 'Contacts::Typed::View::HTML::ContactItem'
} @{$typed->factory_calls};
is(scalar @item_calls, 2, 'view factory constructs one typed item per contact');
is($item_calls[0]{view}->root, $root_view, 'typed item receives the root view');
is($item_calls[0]{view}->parent, $root_view, 'wrapper body retains caller parent scope');
ok(
    !(grep { $_->{class} eq 'Contacts::Typed::View::HTML::Badge' } @{$typed->factory_calls}),
    'preconstructed typed child bypasses the view factory',
);

sub read_file {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh or die "Cannot close $path: $!";
    return $content;
}

my $tutorial_path = File::Spec->catfile(
    $root, qw(lib Template EmbeddedPerl Tutorial.pod),
);
ok(-e $tutorial_path, 'installed tutorial POD exists');

my $tutorial = -e $tutorial_path ? read_file($tutorial_path) : '';
for my $heading (
    'FIRST TEMPLATE',
    'THE CONTACTS APPLICATION',
    'SMART LINES AND NAMED ARGUMENTS',
    'DEFAULTS AND LAZY DEFAULTS',
    'ESCAPING HTML SAFELY',
    'PARTIALS',
    'LAYOUTS',
    'NAMED CONTENT',
    'APPLICATION HELPERS',
    'DIAGNOSING FAILURES',
    'REUSE AND PRODUCTION CONFIGURATION',
    'CHOOSING THE NEXT ABSTRACTION',
) {
    like($tutorial, qr/^=head1 \Q$heading\E$/m, "tutorial contains $heading");
}

like(
    $tutorial,
    qr{examples/contacts/untyped/app\.pl},
    'tutorial points to the runnable untyped application',
);

my $compile_error = eval {
    Template::EmbeddedPerl->from_string(
        "first\n<%= \$missing %>\n",
        source => 'tutorial-compile.epl',
    );
    '';
} || $@;
like(
    $compile_error,
    qr/at tutorial-compile\.epl line 2/,
    'tutorial compile failure reports its template source and line',
);

my $runtime_error = eval {
    Template::EmbeddedPerl->from_string(
        "first\n<% die 'tutorial runtime' %>\n",
        source => 'tutorial-runtime.epl',
    )->render;
    '';
} || $@;
like(
    $runtime_error,
    qr/tutorial runtime at tutorial-runtime\.epl line 2/,
    'tutorial runtime failure reports its template source and line',
);

my @warnings;
{
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    Template::EmbeddedPerl->from_string(
        "first\n<% warn 'tutorial warning' %>\n",
        source => 'tutorial-warning.epl',
    )->render;
}
like(
    join('', @warnings),
    qr/tutorial warning at tutorial-warning\.epl line 2/,
    'tutorial warning reports its template source and line',
);

my $cookbook_path = File::Spec->catfile(
    $root, qw(lib Template EmbeddedPerl Cookbook.pod),
);
ok(-e $cookbook_path, 'installed cookbook POD exists');

my $cookbook = -e $cookbook_path ? read_file($cookbook_path) : '';
for my $heading (
    'WHICH DOCUMENT SHOULD I READ?',
    'RENDERING AND LOADING',
    'TEMPLATE INPUTS',
    'OUTPUT AND ESCAPING',
    'COMPOSITION',
    'SYNTAX AND FORMATTING',
    'HELPERS AND CONFIGURATION',
    'TESTING AND TROUBLESHOOTING',
) {
    like($cookbook, qr/^=head1 \Q$heading\E$/m, "cookbook contains $heading");
}

like(
    $cookbook,
    qr/L<Template::EmbeddedPerl::Tutorial>/,
    'cookbook links newcomers to the tutorial',
);
like(
    $cookbook,
    qr/L<Template::EmbeddedPerl::Cookbook::TypedViews>/,
    'cookbook links framework authors to typed views',
);

done_testing;
