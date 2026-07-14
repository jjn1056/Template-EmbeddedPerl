use strict;
use warnings;

use File::Spec;
use Test::Most;
use Template::EmbeddedPerl;

my $root = File::Spec->rel2abs('.');
my $distribution_lib = File::Spec->catdir($root, 'lib');
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
    my ($script) = @_;
    open my $fh, '-|', $^X, "-I$distribution_lib", $script
        or die "Cannot execute $script: $!";
    local $/;
    my $output = <$fh>;
    close $fh or die "Example $script failed";
    return $output;
}

my $untyped = Contacts::Untyped::App->new(root => $untyped_root);
is($untyped->heading_calls, 0, 'lazy heading default has not run before rendering');
is($untyped->render, $expected_html, 'untyped Contacts application renders expected HTML');
is($untyped->heading_calls, 1, 'absent heading evaluates the lazy default once');

$untyped->render(heading => 'Directory');
is($untyped->heading_calls, 1, 'explicit heading bypasses the lazy default');

is(
    run_script(File::Spec->catfile($untyped_root, 'app.pl')),
    $expected_html,
    'untyped command-line example renders expected HTML',
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

done_testing;
