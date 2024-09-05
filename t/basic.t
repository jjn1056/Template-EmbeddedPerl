package Template::EmbeddedPerl::Test::Basic;
$INC{'Template/EmbeddedPerl/Test/Basic.pm'} = __FILE__;

use Template::EmbeddedPerl;
use Test::Most;
use Devel::Dwarn;
use Cwd 'abs_path';
use File::Basename;

ok my %helpers = (
  ttt => sub { '<a>TTT</a>' },
);

ok my $current_directory = dirname(abs_path(__FILE__));
ok my $yat = Template::EmbeddedPerl->new(helpers=>\%helpers, directories => [[$current_directory, 'templates']]);
ok my $generator1 = $yat->from_data('Template::EmbeddedPerl::Test::Basic');

ok my $out1 = $generator1->render(qw/a b c/);

warn "..$out1..";

ok my $generator2 = $yat->from_file('hello');
ok my $out2 = $generator2->render('John');

warn $out2;

done_testing;

__DATA__
<% my @items = @_ %>\
<%= map { %>\
  <p><%= $_ %></p>
<% } @items %>\\
<% my $X=1; my $bb = safe_concat map { %>\
  <p><%= $_ %></p>
<% } @items %>\
<% if(1) { %>
  <span>One: <%= ttt %></span>
<% } %>\
<% my $a=[1,2,3]; foreach my $item (sub { @items }->()) {
  foreach my $index (0..2) {
    foreach my $i2 (2..3) { =%>\
    <div>
      <%= $item.' '.$index. ' '.$i2 %>
    </div>
  <% }} =%>\
  <%=  sub { =%>\
    <p><%= "A: @{[ $a->[2] ]}" %></p>
  <% }->() =%>\
<% } %>
<%= raw "BB: ..@{[ trim $bb ]}.." %>
<%= 'ddd' %>
