package App::Presenter;

use strict;
use warnings;

use Carp;
use Data::Dumper;
use Data::Page;
use List::Util;
use Plack::Response;
use URI::QueryParam;

use App::I18n;
use App::Router;
use Utilities;

my $TEXT_FIELD_SIZE = 60;
# Number of results pages before and after the current one do we show links to.
my $PAGINATION_CONTEXT = 2;

# For creating index page column labels a Presenter must be instantiated without
# an object. Presdenters should be obj-agnostic when doing labels and only
# care about the object they present when displaying values.
sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{$_} = $args{$_} for keys %args;
  Carp::confess "No controller passed to Presenter" unless $args{controller};
  #Carp::confess "No object passed to Presenter" unless $args{obj};
  return $self;
}

# Can be used in index and other batch processing contexts to swap in
# objects (or hashes posing as objects) in order to reuse a presenter
# while iterating.
# Right now it is not an error to set to undef.
sub set_obj {
  my $self = shift;
  my $obj  = shift;

  $self->{obj} = $obj;
}

# Lowercase version of the object this class is a presenter for.
# Should be implemented by subclasses.
sub model_name {
  my $self  = shift;

  # Generic value that will not generally be used.
  return 'obj';
}

# The prefix for edit fields like 'name' which get submitted as (for example) 'user[name]'.
sub form_field_name {
  my $self  = shift;
  my $field = shift;

  #my $object_name = $self->form_object_name;
  return $self->model_name . '[' . $field . ']';
}

# Alias for translate().
# For use in view templates
sub t {
  my $self = shift;

  return $self->translate(@_);
}

# For use in view templates
sub translate {
  my $self = shift;
  my $key  = shift;

  if ($key =~ m/^\./) {
    $key = $self->i18n_view_prefix . $key;
  }
  return App::I18n::Translate($key, undef, @_);
}

# Subclasses should override this to enable truncated paths:
# QueuePresenter would return 'view.queue' to allow 'view.queue.index.blah'
# to be abbreviated '.index.blah'
# NOTE: this is only for keys in the 'view.*' namespace.
sub i18n_view_prefix {
  my $self = shift;

  my $prefix = 'view';
  return 'view';
}

sub i18n_current_locale {
  my $self = shift;

  return App::I18n::CurrentLocale();
}

sub all_fields {
  my $self = shift;

  return [];
}

sub field_label {
  my $self  = shift;
  my $field = shift;
  my $for   = shift || '';
  my $class = shift || '';

  my $key = 'model.' . $self->model_name . '.attribute.' . $field;
  my $text = App::I18n::Translate($key);
  if (defined $text) {
    $text = Utilities->new->EscapeHTML($text);
  }
  if ($text eq $key) {
    # Appropriate fallback?
    $text .= " (<i>Translation Missing</i>)";
  }
  if ($for || $class) {
    return <<HTML;
<label class="$class" for="$for">$text</label>
HTML
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
    my $translated = App::I18n::Translate('model.' . $self->model_name . '.value.' . $value);
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
  my $id = $field . '-text';
  return <<HTML;
<input id="$id" type="text" value="$value" size="$TEXT_FIELD_SIZE" name="$name"/>
HTML
}

# FIXME: if Data::Page proves well-behaved, classes like Queue and Candidates could return
# a Data::Page object that the view can pass in here rather than recalculating pagination here.
# Displays a series of pagination links sorta like [<<][1]..[6][7][__8__][9][10]..[100][>>]
sub paginate {
  my $self = shift;
  my $total_entries = shift || 0;
  my $current_page = shift || 1;
  my $entries_per_page = shift || 20;

  my $page = Data::Page->new();
  $page->total_entries($total_entries);
  $page->entries_per_page($entries_per_page);
  $current_page = $page->last_page if $current_page > $page->last_page;
  $page->current_page($current_page);
  my $start = List::Util::max(1, $current_page - $PAGINATION_CONTEXT);
  my $end = List::Util::min($page->last_page, $current_page + $PAGINATION_CONTEXT);
  my $html = '<nav aria-label="Page Navigation">';
  $html .= '<ul class="pagination">';
  # Always show previous page link, disabled if we are on the first page
  my $previous_page_class = (defined $page->previous_page)? '' : 'disabled';
  my $previous_page_link = (defined $page->previous_page)? $self->put_param('page', $page->previous_page) : '';
  $html .= <<HTML;
<li class="page-item $previous_page_class">
  <a class="page-link" href="$previous_page_link">&laquo;</a>
</li>
HTML
  # Show first page link if it is not included in the current page context window
  if ($start > 1) {
    my $first_page_link = $self->put_param('page', 1);
    my $first_page_class = ($current_page == 1)? 'disabled' : '';
    $html .= <<HTML;
<li class="page-item $first_page_class">
  <a class="page-link" href="$first_page_link">1</a>
</li>
HTML
    # Show ellipsis link if page 2+ are left out of the window
    if ($start > 2) {
      $html .= <<HTML;
<li class="page-item disabled">
  <a class="page-link" href="">...</a>
</li>
HTML
    }
  }
  foreach my $p ($start .. $end) {
    my $page_item_class = ($current_page == $p)? 'active' : '';
    my $url = $self->put_param('page', $p);
    $html .= <<HTML;
<li class="page-item $page_item_class" aria-current="page">
  <a class="page-link" href="$url">$p</a>
</li>
HTML
  }
  my $last_page = $page->last_page;
  if ($end < $last_page) {
    # Show ellipsis link if next to last page is left out of the window
    if ($end < $page->last_page - 1) {
      $html .= <<HTML;
<li class="page-item disabled">
  <a class="page-link" href="">...</a>
</li>
HTML
    }
    my $last_page_class = ($current_page == $last_page)? 'disabled' : '';
    my $last_page_link = $self->put_param('page', $last_page);
    $html .= <<HTML;
<li class="page-item $last_page_class"> 
  <a class="page-link" href="$last_page_link">$last_page</a>
</li>
HTML
  }
  my $next_page_class = (defined $page->next_page)? '' : 'disabled';
  my $next_page_link = (defined $page->next_page)? $self->put_param('page', $page->next_page) : '';
  $html .= <<HTML;
<li class="page-item $next_page_class">
  <a class="page-link" href="$next_page_link">&raquo;</a>
</li>
HTML
  $html .= "</ul>\n</nav>\n";
  return $html;
}

sub put_param {
  my $self  = shift;
  my $name  = shift;
  my $value = shift;

  return App::Router->new->put_param($name, $value);
}

1;
