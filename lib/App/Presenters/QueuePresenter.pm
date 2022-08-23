package App::Presenters::QueuePresenter;
use parent 'App::Presenter';

use strict;
use warnings;

use App::I18n;
use Project;
use Utilities;

my $SEARCH_MENU_FIELDS = ['id', 'cid', 'title', 'author', 'pub_date', 'country',
 'date', 'status', 'locked', 'priority', 'reviews', 'expert_reviews', 'holds',
 'source', 'added_by', 'project', 'ticket'];

my $INDEX_FIELDS = ['id', 'title', 'author', 'pub_date', 'country', 'date', 'status',
  'locked', 'priority', 'reviews', 'expert_reviews', 'holds', 'source', 'added_by',
  'project', 'ticket'];


sub model_name {
  my $self  = shift;

  return 'queue';
}

sub index_fields {
  my $self = shift;

  return $INDEX_FIELDS;
}

sub i18n_view_prefix {
  my $self = shift;

  return 'view.queue';
}

sub search_menu {
  my $self  = shift;
  my $name  = shift;
  my $value = shift;
  my $class = shift || '';

  my $html = <<HTML;
<select name="$name" id="$name" class="$class">
HTML
  foreach my $field (@$SEARCH_MENU_FIELDS) {
    my $selected = ($value eq $field) ? 'selected' : '';
    my $text = App::I18n::Translate('model.queue.attribute.' . $field);
    $html .= <<HTML;
  <option value="$field" $selected>$text</option>
HTML
  }
  $html .= "</select>\n";
  return $html;
}

sub edit_priority {
  my $self = shift;

  my $pattern = '-?\d(\.\d\d?)?';
  my $priority = $self->{obj}->{priority} || '0';
  return <<HTML;
<input type="text" value="$priority" id="priority-text"
  name="queue[priority]" size="6" pattern="$pattern"/>
HTML
}

sub edit_project {
  my $self = shift;

  my $html = <<HTML;
<select id="project-select" class="select-project" name="queue[project]">
HTML
  foreach my $project (@{Project::All()}) {
    my $selected = '';
    if (defined $self->{obj} && defined $self->{obj}->{project} &&
      $self->{obj}->{project} eq $project->{id}) {
      $html = 'selected';
    }
    my $text = Utilities->new->EscapeHTML($project->{name});
    $html .= <<HTML;
  <option value="$project->{id}" $selected>
    $text
  </option>
HTML
  }
  $html .= "</select>\n";
  return $html;
}

1;
