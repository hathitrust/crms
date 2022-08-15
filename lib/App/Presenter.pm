package App::Presenter;

use strict;
use warnings;

use Carp;
use Plack::Response;

use App::I18n;
use Utilities;

# This should be overridden somehow to give us our localization namespace
#my $NAMESPACE = 'crms.something.something';

my $TEXT_FIELD_SIZE = 60;

# For creating index page column labels a Presenter must be instantiated without
# an object. Presdenters should be obj-agnostic when doing labels and only
# care about the object they present when displaying values.
sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{$_} = $args{$_} for keys %args;
  Carp::confess "No controller passed to Presenter" unless $args{'controller'};
  #Carp::confess "No object passed to Presenter" unless $args{'obj'};
  Carp::confess "No model name passed to Presenter" unless $args{'model'};
  return $self;
}

# # Lowercase version of the object this class is a presenter for.
# # This needs to be implemented by subclasses.
# sub form_object_name {
#   my $self  = shift;
#
#   # Generic value for generic superclass.
#   #return 'obj';
#   Carp::confess "App::Presenter form_object_name should be defined by subclass";
# }

# The prefix for edit fields like 'name' which get submitted as (for example) 'user[name]'.
sub form_field_name {
  my $self  = shift;
  my $field = shift;

  #my $object_name = $self->form_object_name;
  return $self->{model} . '[' . $field . ']';
}

sub all_fields {
  my $self = shift;

  return [];
}

sub field_label {
  my $self  = shift;
  my $field = shift;
  my $form  = shift;

  my $key = 'model.' . $self->{model} . '.attribute.' . $field;
  my $text = App::I18n::Translate($key);
  if (defined $text) {
    $text = Utilities->new->EscapeHTML($text);
  } else {
    # Appropriate fallback?
    $text = "$key (<i>Translation Missing</i>)";
  }
  if (defined $form) {
    return "<label for='$field'>" . $text . "</label>\n";
  }
  return $text;
}

# Call subclass show_<field> if available.
# Otherwise call object-><field> if available.
sub show_field_value {
  my $self  = shift;
  my $field = shift;

  my $method = 'show_' . $field;
  if (my $ref = eval { $self->can($method); }) {
    return $self->$ref();
  }
  my $value = $self->{obj}->{$field};
  if (my $ref = eval { $self->{obj}->can($field); }) {
    $value = $self->{obj}->$ref();
  }
  if (defined $value && length $value) {
    my $translated = App::I18n::Translate('model.' . $self->{model} . '.value.' . $value);
    $value = $translated if defined $translated;
  }
  $value = '' unless defined $value;
  return Utilities->new->EscapeHTML($value);
}

# Call subclass edit_<field> if available.
# Otherwise return <input> with object-><field> if available.
sub edit_field_value {
  my $self  = shift;
  my $field = shift;

  
  my $method = 'edit_' . $field;
  if (my $ref = eval { $self->can($method); }) {
    return $self->$ref();
  }
  my $value = $self->{obj}->{$field} || '';
  if (my $ref = eval { $self->{obj}->can($field); }) {
    $value = $self->{obj}->$ref();
  }
  my $name = $self->form_field_name($field);
  return "<input id='$field' type='text' value='$value'
    size='$TEXT_FIELD_SIZE' name='$name'/>\n";
}

1;
