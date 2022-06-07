package App::Renderer;

use strict;
use warnings;

use Data::Dumper;
use Template;

my $TEMPLATE_TOOLKIT_CONFIG = {
  INCLUDE_PATH => $ENV{'SDRROOT'}. '/crms/views/',
  INTERPOLATE  => 1,     ## expand "$var" in plain text
  POST_CHOMP   => 1,     ## cleanup whitespace
  EVAL_PERL    => 1,     ## evaluate Perl code blocks
  ENCODING     => 'UTF-8'
};


sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{$_} = $args{$_} for keys %args;
  Carp::confess "No vars passed to Renderer" unless $args{'vars'};
  return $self;
}

sub render {
  my $self   = shift;
  my $path   = shift;
  my $layout = shift; # Expected to be 'main' for 'layouts/main.tt'

  my $output = '';
  my $tt = Template->new($TEMPLATE_TOOLKIT_CONFIG);
  # PROCESS PAGE TEMPLATE
  my $template = $self->get_template($path);
  # uncoverable branch true
  if (!$tt->process($template, $self->{vars}, \$output)) {
    my $tt_err = $tt->error; # uncoverable statement
    $tt_err =~ s/\n+/<br\/>\n/gm; # uncoverable statement
    $self->{vars}->{flash}->add('alert', $tt_err); # uncoverable statement
    #$output .= sprintf "<h3>%s</h3>\n", $tt_err; # uncoverable statement
  }
  $layout = $self->get_layout($layout);
  $self->{vars}->{content} = $output;
  $output = '';
  # PROCESS OUTER LAYOUT WITH CONTENT OF INNER TEMPLATE
  if (!$tt->process($layout, $self->{vars}, \$output)) {
    $output .= sprintf "<h3><pre>%s</pre></h3>\n", $tt->error(); # uncoverable statement
  }
  # If displaying vars inline for debugging purposes,
  # it is disconcerting to have the HTML content rendered a second time.
  # Could also wrap it in a <pre> and leave it.
  delete $self->{vars}->{content};
  return $output;
}

sub get_template {
  my $self = shift;
  my $file = shift || 'home';

  $file = $file . '.tt';
  my $path = $TEMPLATE_TOOLKIT_CONFIG->{INCLUDE_PATH} . $file;
  Carp::confess "Unable to find template file $file" unless -f $path;
  return $file;
}

sub get_layout {
  my $self = shift;
  my $file = shift || 'main';

  $file = 'layouts/' . $file . '.tt';
  my $path = $TEMPLATE_TOOLKIT_CONFIG->{INCLUDE_PATH} . $file;
  Carp::confess "Unable to find layout file $file" unless -f $path;
  return $file;
}

1;
