package Template::EmbeddedPerl;

use warnings;
use strict;

use PPI::Document;
use Module::Runtime;
use File::Spec;
use Template::EmbeddedPerl::Compiled;
use Template::EmbeddedPerl::Utils qw(normalize_linefeeds generate_error_message);
use Template::EmbeddedPerl::SafeString;

## New Instance of the core template methods

sub raw { my ($self, @args) = @_; return Template::EmbeddedPerl::SafeString::raw(@args) }
sub safe { my ($self, @args) = @_; return Template::EmbeddedPerl::SafeString::safe(@args) }
sub safe_concat { my ($self, @args) = @_; return Template::EmbeddedPerl::SafeString::safe_concat(@args) }
sub html_escape { my ($self, @args) = @_; return Template::EmbeddedPerl::SafeString::html_escape(@args) }
sub url_encode { my ($self, @args) = @_; return Template::EmbeddedPerl::Utils::uri_escape(@args) }
sub escape_javascript { my ($self, @args) = @_; return Template::EmbeddedPerl::Utils::escape_javascript(@args) }

sub trim {
  my ($self, $string) = @_;
  $string =~ s/^\s+|\s+$//g;
  return $string;
}

sub new {
  my $class = shift;
  my (%args) = (
    open_tag => '<%',
    close_tag => '%>',
    expr_marker => '=',
    sandbox_ns => 'Template::YAT::Sandbox',
    directories => [],
    template_extension => 'yat',
    auto_escape => 0,
    auto_flatten_expr => 1,
    prepend => '',
    @_,
  );

  my $self = bless \%args, $class;

  $self->inject_helpers;
  return $self;
}

sub inject_helpers {
  my ($self) = @_;
  my %helpers = $self->get_helpers;
  foreach my $helper(keys %helpers) {
    eval qq[
      package @{[ $self->{sandbox_ns} ]};
      sub $helper { \$self->get_helpers('$helper')->(\$self, \@_) }
    ]; die $@ if $@;
  }
}

sub get_helpers {
  my ($self, $helper) = @_;
  my %helpers = ($self->default_helpers, %{ $self->{helpers} || +{} });
 
  return $helpers{$helper} if defined $helper;
  return %helpers;
}

sub default_helpers {
  my $self = shift;
  return (
    raw               => sub { my ($self, @args) = @_; return $self->raw(@args); },
    safe              => sub { my ($self, @args) = @_; return $self->safe(@args); },
    safe_concat       => sub { my ($self, @args) = @_; return $self->safe_concat(@args); },
    html_escape       => sub { my ($self, @args) = @_; return $self->rhtml_escape(@args); },
    url_encode        => sub { my ($self, @args) = @_; return $self->url_encode(@args); },
    escape_javascript => sub { my ($self, @args) = @_; return $self->escape_javascript(@args); },
    trim             => sub { my ($self, $arg) = @_; return $self->trim($arg); },
  );
}

# Create a new template document in various ways

sub from_string {
  my ($proto, $template, %args) = @_;
  my $source = delete($args{source});
  my $self = ref($proto) ? $proto : $proto->new(%args);

  $template = normalize_linefeeds($template); ## TODO: think about this, maybe =]] instead

  my @template = split(/\n/, $template);
  my @parsed = $self->parse_template($template);
  my $code = $self->compile(\@template, $source, @parsed);

  $self->{template} = \@template;
  $self->{parsed} = \@parsed;
  $self->{code} = $code;

  return bless {
    template => \@template,
    parsed => \@parsed,
    code => $code,
    yat => $self,
    source => $source,
  }, 'Template::EmbeddedPerl::Compiled'; 
}

sub from_data {
  my ($proto, $package, @args) = @_;

  eval "require $package;"; if ($@) {
    die "Failed to load package $package $@";
  }

  my $data_handle = do { no strict 'refs'; *{"${package}::DATA"}{IO} };
  if (defined $data_handle) {
    my $data_content = do { local $/; <$data_handle> };
    my $package_file = $package;
    $package_file =~ s/::/\//g;
    my $path = $INC{"${package_file}.pm"};
    return $proto->from_string($data_content, @args, source => $path);
  } else {
    print "No __DATA__ section found in package $package.\n";
  }
}

sub from_fh {
  my ($proto, $fh, @args) = @_;
  my $data = do { local $/; <$fh> };
  close $fh;

  return $proto->from_string($data, @args);
}

sub from_file {
  my ($proto, $file_proto, @args) = @_;
  my $self = ref($proto) ? $proto : $proto->new(@args);
  my $file = "${file_proto}.@{[ $self->{template_extension} ]}";

  # find if it exists in the directories
  foreach my $dir (@{ $self->{directories} }) {
    $dir = File::Spec->catdir(@$dir) if ((ref($dir)||'') eq 'ARRAY');
    my $path = File::Spec->catfile($dir, $file);
    if (-e $path) {
      open my $fh, '<', $path or die "Failed to open file $path: $!";
      my %args = (@args, source => $path);
      return $self->from_fh($fh, %args);
    }
  }
  die "File $file not found in directories: @{[ join ', ', @{ $proto->{directories} } ]}";
}

# Methods to parse and compile the template

sub parse_template {
  my ($self, $template) = @_;
  my $open_tag = $self->{open_tag};
  my $close_tag = $self->{close_tag};
  my $expr_marker = $self->{expr_marker};


  # This code parses the template and returns an array of parsed blocks.
  # Each block is represented as an array reference with two elements: the type and the content.
  # The type can be 'expr' for expressions enclosed in double square brackets,
  # 'code' for code blocks enclosed in double square brackets,
  # or 'text' for plain text blocks.
  # The content is the actual content of the block, trimmed of leading and trailing whitespace.

  my @segments = split /(\Q${open_tag}\E.*?\Q${close_tag}\E)/s, $template;
  my @parsed = ();
  foreach my $segment (@segments) {
    my ($open_type, $content, $close_type) = ($segment =~ /^(\Q${open_tag}${expr_marker}\E|\Q$open_tag\E)(.*?)(\Q${expr_marker}${close_tag}\E|\Q$close_tag\E)?$/s);

    if(!$open_type) {
      push @parsed, ['text', $segment];
    } else {
      $parsed[-1][1] =~s/[ \t]+$//mg if $close_type eq "${expr_marker}${close_tag}";
      if ($open_type eq "${open_tag}${expr_marker}") {
        push @parsed, ['expr', tokenize($content)];
      } elsif ($open_type eq $open_tag) {
        push @parsed, ['code', tokenize($content)];
      }
    }
  }

  return @parsed;
}

sub compile {
  my ($self, $template, $source, @parsed) = @_;

  my $compiled = '';
  my $safe_or_not = $self->{auto_escape} ? ' safe ' : '';
  my $flatten_or_not = $self->{auto_flatten_expr} ? ' join "", ' : '';

  for my $block (@parsed) {
    next if $block eq '';
    my ($type, $content, $has_unmatched_open, $has_unmatched_closed) = @$block;

    if ($type eq 'expr') { # [[= ... ]]
      $compiled .= '$_O .= ' . $flatten_or_not . $safe_or_not . $content . ";";
    } elsif ($type eq 'code') { # [[ ... ]]
      $compiled .= $content . ";";
    } else {
      # if \\n is present in the content, replace it with ''
      my $escaped_newline = $content =~ s/^\\\n//;
      $content =~ s/^\\\\/\\/;   
      $compiled .= "\$_O .= \"" . quotemeta($content) . "\";";
      $compiled .= "\n" if $escaped_newline;
    }
  }

  $compiled = "use strict; use warnings; use utf8; @{[ $self->{prepend} ]}; sub { my \$_O = ''; $compiled; return \$_O; }";
  $compiled = "package @{[ $self->{sandbox_ns} ]}; $compiled";

  # Tweak the error message of trying to compile the template so that
  # it shows the line number and the surrounding lines of the template
  # and generally makes it easier to debug the template.

  print "Compiled: $compiled\n" if $ENV{DEBUG_TEMPLATE_EMBEDDED_PERL};

  my $code = eval $compiled; if($@) {
    die generate_error_message($@, $template, $source);
  }

  return $code;
}

sub tokenize {
  my $content = shift;
  my $document = PPI::Document->new(\$content);
  my ($has_unmatched_open, $has_unmatched_closed) = mark_unclosed_blocks($document);
  return ($document, $has_unmatched_open, $has_unmatched_closed);
}


sub mark_unclosed_blocks {
  my ($element) = @_;
  my $blocks = $element->find('PPI::Structure::Block');
  my $has_unmatched_open = mark_unclosed_open_blocks($element); 
  my $has_unmatched_closed = mark_unmatched_close_blocks($element);

  return ($has_unmatched_open, $has_unmatched_closed);
}

sub is_control_block {
  my ($block) = @_;

  # Get the parent of the block
  my $parent = $block->parent;

    # Check if the parent is a control statement
  if ($parent && $parent->isa('PPI::Statement::Compound')) {
    my $keyword = $parent->schild(0); # Get the first child of the statement, which should be the control keyword

    if ($keyword && $keyword->isa('PPI::Token::Word')) {
      # Check if the keyword is a control structure keyword
      return 1 if $keyword->content =~ /^(if|else|elsif|while|for|foreach|unless|given|when|until)$/;
    }
  }

  return 0;
}

sub mark_unclosed_open_blocks {
  my ($element, $level) = @_;
  my $blocks = $element->find('PPI::Structure::Block');
  return unless $blocks;

  my $has_unmatched_open = 0;
  foreach my $block (@$blocks) {
    next if $block->finish; # Skip if closed
    next if is_control_block($block);
    $has_unmatched_open = 1;
    
    my @children = @{$block->{children}||[]};
    $block->{children} = [
      bless({ content => " " }, 'PPI::Token::Whitespace'),
      bless({
        children => [
          bless({ content => " " }, 'PPI::Token::Whitespace'),
          bless({
            children => [
              bless({ content => "my" }, 'PPI::Token::Word'),
              bless({ content => " " }, 'PPI::Token::Whitespace'),
              bless({ content => "\$_O" }, 'PPI::Token::Symbol'),
              bless({ content => "=" }, 'PPI::Token::Operator'),
              bless({ content => "\"\"", separator => "\"" }, 'PPI::Token::Quote::Double'),
            ],
          }, 'PPI::Statement::Variable'),
          @children,
        ],
      }, 'PPI::Statement'),
    ];
  }
  return $has_unmatched_open;
}

sub mark_unmatched_close_blocks {
  my ($element, $level) = @_;
  my $blocks = $element->find('PPI::Statement::UnmatchedBrace');
  return unless $blocks;

  foreach my $block (@$blocks) {
    next if $block eq ')'; # we only care about }
    my @children = @{$block->{children}||[]};
    $block->{children} = [
      bless({ content => 'raw' }, 'PPI::Token::Word'),
      bless({
          children => [
              bless({
                  children => [
                      bless({ content => '$_O' }, 'PPI::Token::Symbol'),
                  ],
              }, 'PPI::Statement::Expression'),
          ],
          start  => bless({ content => '(' }, 'PPI::Token::Structure'),
          finish => bless({ content => ')' }, 'PPI::Token::Structure'),
      }, 'PPI::Structure::List'),
      bless({ content => ';' }, 'PPI::Token::Structure'),
      @children,
    ],
  }
  return 1;
}

1;

=head1 NAME

Template::EmbeddedPerl - A template processing module for embedding Perl code

=head1 SYNOPSIS

  use Template::EmbeddedPerl;

  # Create a new template object
  my $template = Template::EmbeddedPerl->new();

  # Compile a template from a string
  my $compiled = $template->from_string('Hello, <%= shift %>!');

  # execute the compiled template
  my $output = $compiled->render('John');

  # $output is:
  Hello, John!

=head1 DESCRIPTION

C<Template::EmbeddedPerl> is a template engine that allows you to embed Perl code
within template files or strings. It provides methods for creating templates
from various sources, including strings, file handles, and data sections.

The module also supports features like helper functions, custom template tags,
automatic escaping, and customizable sandbox environments.

Its quite similar to L<Mojo::Template> and other embedded Perl template engines
but its got one trick the others can't do (see L<EXCUSE> below).

=head1 ACKNOWLEDGEMENTS

I looked at L<Mojo::Template> and I lifted some code and docs from there.  I also
copied some of ther test cases.   I was shooting for something reasonable similar
and potentially compatible with L<Mojo::Template> but with some additional features.
L<Template::EmbeddedPerl> is similiar to how template engines in popular frameworks 
like Ruby on Rails and also similar to EJS in the JavaScript world.  So nothing weird
here, just something people would understand and be comfortable with.  A type of
lowest common denominator.  If you know Perl, you will be able to use this after
a few minutes of reading the docs (or if you've used L<Mojo::Template> or L<Mason>
you might not even need that).

=head1 EXCUSE

Why create yet another one of these embedded Perl template engines?  I wanted one
that could properly handle block capture like following:

    <% my @items = map { %>
      <p><%= $_ %></p>
    <% } @items %>

Basically none of the existing ones I could find could handle this.  If I'm wrong
and somehow there's a flag or approach in L<Mason> or one of the other ones that
can handle this please let me know.

L<Mojo::Template> is close but you have to use C<begin> and C<end> tags to get a similar
effect and it's not as flexible as I'd like plus I want to be able to use signatures in
code like the following:

    <%= $f->form_for($person, sub($view, $fb, $person) { %>
      <div>
        <%= $fb->label('first_name') %>
        <%= $fb->input('first_name') %>
        <%= $fb->label('last_name') %>
        <%= $fb->input('last_name') %>
      </div>
    <% }) %>

Again, I couldn't find anything that could do this.   Its actually tricky because of the way
you need to localize capture of template output when inside a block.  I ended up using L<PPI>
to parse the template so I could properly find begin and end blocks and also distinguish between
control blocks (like C<if> an C<unless>) blocks that have a return like C<sub> or C<map> blocks.
In L<Mojo::Template> you can do the following (its the same but not as pretty to my eye):

    <% my $form = $f->form_for($person, begin %>
      <% my ($view, $fb, $person) = @_; %>
      <div>
        <%= $fb->label('first_name') %>
        <%= $fb->input('first_name') %>
        <%= $fb->label('last_name') %>
        <%= $fb->input('last_name') %>
      </div>
    <% end; %>

On the other hand my system is pretty new and I'm sure there are bugs and issues I haven't
thought of yet.  So you probably want to use one of the more mature systems like L<Mason> or
L<Mojo::Template> unless you really need the features I've added. Or your being forced to use
it because you're working for me ;)

=head1 TEMPLATE SYNTAX

The template syntax is similar to other embedded Perl template engines. You can embed Perl
code within the template using opening and closing tags. The default tags are C<< '<%' >> and
C<< '%>' >>, but you can customize them when creating a new template object.

All templates get C<strict>, C<warnings> and C<utf8> enabled by default.  Please note this
is different than L<Mojo::Template> which does not seem to have warnings enabled by default.
Since I like very strict templates this default makes sense to me but if you tend to play
fast and loose with your templates (for example you don't use C<my> to declare variables) you
might not like this.  Feel free to complain to me, I might change it.

  <% Perl code %>
  <%= Perl expression, replaced with result %>

You can add '=' to the closing tag to indicate that the expression should be trimmed of leading
and trailing whitespace. This is useful when you want to include the expression in a block of text.

  <% Perl code =%>
  <%= Perl expression, replaced with result, trimmed =%>

If you want to skip the newline after the closing tag you can use a backslash.

  <% Perl code %>\
  <%= Perl expression, replaced with result, trimmed %>\

You probably don't care about this so much with HTML since it collapses whitespace but it can be
useful for other types of output like plain text or if you need some embedded Perl inside
your JavaScript.

=head1 METHODS

=head2 new

  my $template = Template::EmbeddedPerl->new(%args);

Creates a new C<Template::EmbeddedPerl> object. Accepts the following arguments:

=over 4

=item * C<open_tag>

The opening tag for template expressions. Default is C<< '<%' >>.

=item * C<close_tag>

The closing tag for template expressions. Default is C<< '%>' >>.

=item * C<expr_marker>

The marker indicating a template expression. Default is C<< '=' >>.

=item * C<sandbox_ns>

The namespace for the sandbox environment. Default is C<< 'Template::YAT::Sandbox' >>.

=item * C<directories>

An array reference of directories to search for templates. Default is an empty array.
A directory to search can be either a string or an array reference containing each part
of the path to the directory.  Directories will be searched in order listed.

=item * C<template_extension>

The file extension for template files. Default is C<< 'yat' >>.

=item * C<auto_escape>

Boolean indicating whether to automatically escape content. Default is C<< 0 >>.
You probably want this enabled for web content to prevent XSS attacks.

=item * C<auto_flatten_expr>

Boolean indicating whether to automatically flatten expressions. Default is C<< 1 >>.
What this means is that if you have an expression that returns an array we will join
the array into a string before outputting it.

=item * C<prepend>

Perl code to prepend to the compiled template. Default is an empty string. For example
you can enable modern Perl features like signatures by setting this to C<< 'use v5.40;' >>.


=back

=head2 from_string

  my $compiled = $template->from_string($template_string, %args);

Creates a compiled template from a string. Accepts the template content as a
string and optional arguments to modify behavior. Returns a
C<Template::EmbeddedPerl::Compiled> object.

pass 'source => $path' to the arguments to specify the source of the template if you
want neater error messages.

=head2 from_file

  my $compiled = $template->from_file($file_name, %args);

Creates a compiled template from a file. Accepts the filename (without extension)
and optional arguments. Searches for the file in the directories specified during
object creation.

=head2 from_fh

  my $compiled = $template->from_fh($filehandle, %args);

Creates a compiled template from a file handle. Reads the content from the
provided file handle and processes it as a template.

pass 'source => $path' to the arguments to specify the source of the template if you
want neater error messages.

=head2 from_data

  my $compiled = $template->from_data($package, %args);

Creates a compiled template from the __DATA__ section of a specified package.
Returns a compiled template object or dies if the package cannot be loaded or
no __DATA__ section is found.

=head2 trim

  my $trimmed = $template->trim($string);

Trims leading and trailing whitespace from the provided string. Returns the
trimmed string.

=head2 default_helpers

  my %helpers = $template->default_helpers;

Returns a hash of default helper functions available to the templates.

=head2 get_helpers

  my %helpers = $template->get_helpers($helper_name);

Returns a specific helper function or all helper functions if no name is provided.

=head2 parse_template

  my @parsed = $template->parse_template($template);

Parses the provided template content and returns an array of parsed blocks.

=head2 compile

  my $code = $template->compile($template, @parsed);

Compiles the provided template content into executable Perl code. Returns a
code reference.

=head1 HELPER FUNCTIONS

The module provides a set of default helper functions that can be used in templates.

=over 4

=item * C<raw>

Returns a string as a safe string object without escaping.   Useful if you
want to return actual HTML to your template but you better be 
sure that HTML is safe.

=item * C<safe>

Returns a string as a safe html escaped string object that will not be 
escaped again.

=item * C<safe_concat>

Like C<safe> but for multiple strings.  This will concatenate the strings into
a single string object that will not be escaped again.

=item * C<html_escape>

Escapes HTML entities in a string.  This differs for C<safe> in that it will
just do the escaping and not wrap the string in a safe string object.

=item * C<url_encode>

Encodes a string for use in a URL.

=item * C<escape_javascript>

Escapes JavaScript entities in a string. Useful for making strings safe to use
 in JavaScript.

=item * C<trim>

Trims leading and trailing whitespace from a string.

=back


=head1 DEDICATION

This module is dedicated to the memory of my dog Bear who passed away 17 August 2024.
He was a good dog and I miss him.

If this module is useful to you please consider donating to your local animal shelter
or rescue organization.

=head1 AUTHOR

Your Name, C<< <jjnapiork@cpan.org> >>

=head1 LICENSE AND COPYRIGHT

This library is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut


__END__
%= join '', map {
  <p>%= $_</p>
} @items;
% my $X=1; my $bb = join '', map {
  <p>%= $_</p>
} @items;
% if(1)
  <span>One: %= ttt</span>
}
% my $a=[1,2,3]; foreach my $item (sub { @items }->()) {
  foreach my $index (0..2) {
    foreach my $i2 (2..3) {
    <div>
      %= $item.' '.$index. ' '.$i2
    </div>
  }}
  %= sub {
    <p>%= "A: @{[ $a->[2] ]}" %%</p>
  }->();
}
%= "BB: $bb"


todo

1 docs
2 add %% and %= support for start of line
4 vars support for hashy render
5 better control of first line for adding modules and pragmas
3 tests
4 tweak the syntax....?

