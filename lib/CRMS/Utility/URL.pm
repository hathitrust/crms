package CRMS::Utility::URL;

use strict;
use warnings;
use utf8;

use CRMS::Version;
use File::stat;
use Time::localtime;
use File::Spec;

# This is a stateless class so it's fine for the singleton pattern.
my $ONE_TRUE_UTILITY_URL;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;

  if (!defined $ONE_TRUE_UTILITY_URL) {
    $ONE_TRUE_UTILITY_URL = $self;
  }
  return $ONE_TRUE_UTILITY_URL;
}

sub css_url {
  my $self = shift;
  my $file = shift;

  return "/crms/public/styles/$file" . $self->_css_cache_buster($file);
}

sub js_url {
  my $self = shift;
  my $file = shift;

  return "/crms/public/scripts/$file" . $self->_js_cache_buster($file);
}

# Cache busters use the modification time of the file in question.
sub _css_cache_buster {
  my $self = shift;
  my $file = shift;

  my $filename = File::Spec->catfile($ENV{SDRROOT}, 'crms', 'public', 'styles', $file);
  my $date_string = File::stat::stat($filename)->mtime;
  return "?v=$date_string";
}

sub _js_cache_buster {
  my $self = shift;
  my $file = shift;

  my $filename = File::Spec->catfile($ENV{SDRROOT}, 'crms', 'public', 'scripts', $file);
  my $date_string = File::stat::stat($filename)->mtime;
  return "?v=$date_string";
}

1;

