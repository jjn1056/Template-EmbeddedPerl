#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use Contacts::Untyped::App;

print Contacts::Untyped::App->new(root => $FindBin::Bin)->render;
