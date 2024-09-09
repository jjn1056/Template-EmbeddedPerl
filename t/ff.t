package Template::EmbeddedPerl::Test::FF;
$INC{'Template/EmbeddedPerl/Test/FF.pm'} = __FILE__;

use Template::EmbeddedPerl;
use Valiant::HTML::Util::View;
use Valiant::HTML::Util::Form;
use Test::Most;
use Cwd 'abs_path';
use File::Basename;
use File::Spec;

{
  package Local::Person;

  use Moo;
  use Valiant::Validations;

  has first_name => (is=>'ro');
  has last_name => (is=>'ro');
  has persisted => (is=>'rw', required=>1, default=>0);
  
  validates ['first_name', 'last_name'] => (
    length => {
      maximum => 10,
      minimum => 3,
    }
  );
}

ok my $current_directory = dirname(abs_path(__FILE__));
ok my $yat = Template::EmbeddedPerl->new(
  auto_escape => 1,
  directories => [[$current_directory, 'templates']],
  prepend => 'use v5.40;use strictures 2;');

ok my $f = Valiant::HTML::Util::Form->new(view=>$yat);
ok my $person = Local::Person->new(first_name => 'aa', last_name => 'napiorkowski');

#ok my $template = join '', <DATA>;
#ok my $generator1 = $yat->from_string($template);
#ok my $generator1 = $yat->from_file('ff');
ok my $generator1 = $yat->from_data(__PACKAGE__);

#open(my $fh, '<', File::Spec->catfile($current_directory, 'templates','ff.yat')) || die "trouble opening file: $@";
#ok my $generator1 = $yat->from_fh($fh, source=>'ff.yat');
#close($fh);


ok my $out = $generator1->render($f, $person);

warn "...$out...";



done_testing;



__DATA__
<% my ($f, $person) = @_ %>
<%= $f->form_for($person, sub($view, $fb, $person) { %>
  <div>
    <%= $fb->label('first_name') %>
    <%= $fb->input('first_name') %>
    <%= $fb->label('last_name') %>
    <%= $fb->input('last_name') %>
  </div>
<% }) %>