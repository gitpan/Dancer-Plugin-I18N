package TestApp;

use Dancer;
use Dancer::Plugin::I18N;

use Data::Dumper;
get '/' => sub { template 'index'; };

1;
