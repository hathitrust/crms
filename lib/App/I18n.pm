package App::I18n;

# Rails-style localization.
# Uses the familiar Rails dotted namespace notation but does not support shortcuts
# based on view/controller scope.

use strict;
use warnings;

use Carp;
use Data::Dumper;
use YAML;

my $DEFAULT_LOCALE = 'en';
my $CURRENT_LOCALE = $DEFAULT_LOCALE;
# Map region codes to dictionaries
my $LOCALE_TO_HASH = {};


# FIXME: fall back to default locale if missing and not set to default.
sub Translate {
  my $key    = shift;
  my $locale = shift || $CURRENT_LOCALE;

# if (scalar(keys @_) % 2 == 1) {
#   my @a = @_;
#   Carp::confess("Odd number of arguments in Translate params: " . Dumper \@a);
# } 
  my %keys = @_;
  my $hash = __locale_hash($locale);
  my @components = split /\./, $key;
  my $translation;
  while (my $subkey = shift @components) {
    my $res = $hash->{$subkey};
    if (ref $res eq 'HASH') {
      $hash = $res;
    }
    if (ref $res eq '' && scalar @components == 0) {
      $translation = $res;
    }
  }
  # Fall back to default translation
  unless (defined $translation ) {
    if ($locale ne $CURRENT_LOCALE) {
      $translation = Translate($key, undef, %keys);
    }
  }
  return $key unless defined $translation;
  # Simple-minded interpolation of %{key} placeholders. 
  $translation =~ s/%\{([A-Za-z_]+)\}%/$keys{$1} || "ERROR: no interpolation for '$1'"/eg;
  return $translation;
}

# Is there any reason not to just use the global variable?
sub CurrentLocale {
  return $CURRENT_LOCALE;
}

# Throws an error if the locale does not exist or can't be read.
sub SetLocale {
  my $locale = shift || $DEFAULT_LOCALE;

  my $h = __locale_hash($locale);
  if (defined $h) {
    $LOCALE_TO_HASH->{$locale} = $h;
    $CURRENT_LOCALE = $locale;
  }
}

sub LocaleHash {
  return __locale_hash(@_);
}

sub __locale_hash {
  my $locale = shift || $CURRENT_LOCALE;

  return $LOCALE_TO_HASH->{$locale} if defined $LOCALE_TO_HASH->{$locale};

  my $locale_file = __locale_path() . $locale . '.yml';
  return unless -f $locale_file;
  my $struct = YAML::LoadFile($locale_file);
  unless (defined $struct->{$locale}) {
    Carp::confess "YAML structure doesn't have a top-level entry for '$locale'";
  }
  return $struct->{$locale};
}

sub __locale_path {
  my $locale = shift;

  my $path = $ENV{SDRROOT};
  $path .= '/' unless $path =~ m/\/$/;
  $path .= 'crms/config/locales/';
  return $path;
}


sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{$_} = $args{$_} for keys %args;
  return $self;
}

sub t {
  my $self = shift;

  return Translate(@_);
}

1;
