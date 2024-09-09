use Mojo::Template;
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
ok my $view = Valiant::HTML::Util::View->new(aaa=>1,bbb=>2, person=>$person);
ok my $f = Valiant::HTML::Util::Form->new(view=>$view);

ok !$person->valid;

ok my $template = join '', <DATA>;
ok my $mojo = Mojo::Template->new(vars=>1, auto_escape => 1);

$mojo->parse($template);
my $out = $mojo->process({items=>'<a>link</a>', f=>$f, person=>$person});

use Devel::Dwarn;
warn $mojo->code;

warn "...$out...";


=over 4

$_O .= "\n";
$_O .= "\<p\>";$_O .= scalar +  $items ;$_O .= "\<\/p\>\n";
$_O .= scalar +  $f->form_for($person, sub { my $_O = ''; $_O .= "\n";
$_O .= "\ \ "; my ($view, $fb, $person) = @_; $_O .= "\n";
$_O .= "\ \ \<div\>\n";
$_O .= "\ \ \ \ ";$_O .= scalar +  $fb->label('first_name') ;$_O .= "\n";
$_O .= "\ \ \ \ ";$_O .= scalar +  $fb->input('first_name') ;$_O .= "\n";
$_O .= "\ \ \ \ ";$_O .= scalar +  $fb->label('last_name') ;$_O .= "\n";
$_O .= "\ \ \ \ ";$_O .= scalar +  $fb->input('last_name') ;$_O .= "\n";
$_O .= "\ \ \<\/div\>\n";
return Mojo::ByteStream->new($_O) }; $_O .= "\n"; at t/ml.t line 37, <DATA> line 11.

with autoescape

$_O .= "\<p\>";$_O .= _escape scalar +  $items ;$_O .= "\<\/p\>\n";
$_O .= _escape scalar +  $f->form_for($person, sub { my $_O = ''; $_O .= "\n";
$_O .= "\ \ "; my ($view, $fb, $person) = @_; $_O .= "\n";
$_O .= "\ \ "; my $a = 1; $_O .= "\n";
$_O .= "\ \ \<div\>\n";
$_O .= "\ \ \ \ ";$_O .= _escape scalar +  $fb->label('first_name') ;$_O .= "\n";
$_O .= "\ \ \ \ ";$_O .= _escape scalar +  $fb->input('first_name') ;$_O .= "\n";
$_O .= "\ \ \ \ ";$_O .= _escape scalar +  $fb->label('last_name') ;$_O .= "\n";
$_O .= "\ \ \ \ ";$_O .= _escape scalar +  $fb->input('last_name') ;$_O .= "\n";
$_O .= "\ \ \<\/div\>\n";
return Mojo::ByteStream->new($_O) }); $_O .= "\n"; at t/ml.t line 37.
=cut

done_testing;



__DATA__
<% my $de =1;
use strict;
use warnings;
 my $g = 1; %>
<%= sub($a) { return $a; }->(1) %>
<p><%= $items %></p>
<% if(1) { %>
  <span>One: <%= 'gg' %></span>
<% } %>
<%= $f->form_for($person, begin %>
  <% my ($view, $fb, $person) = @_; %>
  <% my $a = 1; %>
  <div>
    <%= $fb->label('first_name') %>
    <%= $fb->input('first_name') %>
    <%= $fb->label('last_name') %>
    <%= $fb->input('last_name') %>
  </div>
<% end); %>
