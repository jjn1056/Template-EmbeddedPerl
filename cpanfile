requires 'PPI';
requires 'PathTools';
requires 'Exporter';
requires 'HTML::Escape';
requires 'Scalar::Util';
requires 'Carp';
requires 'URI::Escape';

on test => sub {
  requires 'Test::Most' => '0.34';
};
