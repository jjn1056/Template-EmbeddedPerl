package Template::EmbeddedPerl;

use warnings;
use strict;

use PPI::Document;
use Module::Runtime;
use File::Spec;
use Template::EmbeddedPerl::Compiled;
use Template::EmbeddedPerl::Utils qw(normalize_linefeeds);
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
  my ($class, %args) = (
    shift,
    open_tag => '<%',
    close_tag => '%>',
    expr_marker => '=',
    sandbox_ns => 'Template::YAT::Sandbox',
    directories => [],
    template_extension => 'yat',
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
  my ($proto, $template, @args) = @_;
  my $self = ref($proto) ? $proto : $proto->new(@args);

  $template = normalize_linefeeds($template); ## TODO: think about this, maybe =]] instead

  my @template = split(/\n/, $template);
  my @parsed = $self->parse_template($template);
  my $code = $self->compile(@parsed);

  $self->{template} = \@template;
  $self->{parsed} = \@parsed;
  $self->{code} = $code;

  return bless {
    template => \@template,
    parsed => \@parsed,
    code => $code,
    yat => $self,
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
    return $proto->from_string($data_content, @args);
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
      return $self->from_fh($fh);
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
  my ($self, @parsed) = @_;

  my $compiled = '';
  for my $block (@parsed) {
    next if $block eq '';
    my ($type, $content, $has_unmatched_open, $has_unmatched_closed) = @$block;

    if ($type eq 'expr') { # [[= ... ]]
      $compiled .= '$_O .= safe_concat ' . $content . ";";
    } elsif ($type eq 'code') { # [[ ... ]]
      $compiled .= $content . ";";
    } else {
      # if \\n is present in the content, replace it with ''
      $content =~ s/^\\\n//;
      $content =~ s/^\\\\/\\/;   
      $compiled .= "\$_O .= \"" . quotemeta($content) . "\";"
    }
  }

  $compiled = "use strict; use warnings; sub { my \$_O = ''; $compiled; return \$_O; }";
  $compiled = "package @{[ $self->{sandbox_ns} ]}; $compiled";

  warn $compiled;

  my $code = eval $compiled;
  die $@ if $@;



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
      %= $item.' '.$index. ' '.$i2 %%
    </div>
  }}
  %= sub {
    <p>%= "A: @{[ $a->[2] ]}" %%</p>
  }->();
}
%= "BB: $bb"


todo

1 handle errors
2 auto escape is an option off by default
3 docs
4 tests
5 tweak the syntax....?
6 add %% and %= support for start of line
