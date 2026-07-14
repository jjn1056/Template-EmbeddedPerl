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

done_testing;
