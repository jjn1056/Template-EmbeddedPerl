use Template::EmbeddedPerl;
use Valiant::HTML::Util::View;
use Valiant::HTML::Util::Form;
use Test::Most;

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

ok my $person = Local::Person->new(first_name => 'aa', last_name => 'napiorkowski');
ok my $yat = Template::EmbeddedPerl->new();
ok my $f = Valiant::HTML::Util::Form->new(view=>$yat);

ok !$person->valid;

ok my $template = join '', <DATA>;
ok my $generator1 = $yat->from_string($template, auto_escape => 1);

ok my $out = $generator1->render($f, $person);

warn "...$out...";



done_testing;



__DATA__
<% use v5.40 %>
<% my ($f, $person) = @_ %>
<% my $form = $f->form_for($person, sub($view, $fb, $person) { %>
  <div>
    <%= $fb->label('first_name') %>
    <%= $fb->input('first_name') %>
    <%= $fb->label('last_name') %>
    <%= $fb->input('last_name') %>
  </div>
<% }) %>
And now for the form:
<%= $form %>
