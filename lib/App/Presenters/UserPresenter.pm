package App::Presenters::UserPresenter;
use parent 'App::Presenter';

use strict;
use warnings;

#use User;
use Institution;
use Utilities;

my $ALL_FIELDS = ['id', 'email', 'name', 'reviewer', 'advanced', 'expert', 'admin',
  'role', 'note', 'institution', 'commitment', 'project', 'active', 'internal'];

sub form_object_name {
  my $self  = shift;

  return 'user';
}

sub all_fields {
  my $self = shift;

  return $ALL_FIELDS;
}

sub show_institution {
  my $self = shift;

  return $self->{obj}->institution->{name};
}

sub show_note {
  my $self = shift;

  my $note = $self->{obj}->{note} || '';
  return "<textarea rows=\"3\" cols=\"20\" readonly>$note</textarea>\n";
}

sub show_projects {
  my $self = shift;

  my @names = map { Utilities->new->EscapeHTML($_->{name}); } @{$self->{obj}->projects};
  my $html;
  if (scalar @names < 2) {
    $html = join ', ', @names;
  } else {
    my $names = join '<br/>', @names;
    $html = "<img width='16' height='16' alt='Multiple Projects'
                  src='/crms/web/help.png' data-bs-toggle='tooltip'
                  data-bs-html='true' title='$names'>";
  }
  return $html;
# FIXME: FIND A BOOTSTRAP-COMPATIBLE WAY OF DOING THIS
#   [% IF u.projects.size > 1 %]
#           [% names = [] %]
#           [% FOREACH proj IN u.projects %]
#             [% names.push(proj.name) %]
#           [% END %]
#           [% tip = "<strong>Projects:</strong>" %]
#           [% FOREACH name IN names.sort %]
#             [% tip = tip _ '<br/>' _ name %]
#           [% END %]
#           <img class="tippy" width="16" height="16" alt="Multiple Projects"
#                src="[% crms.WebPath('web', 'help.png') %]"
#                data-tippy-content="[% utils.EscapeHTML(tip) %]"/>
#         [% ELSIF u.projects.size == 1 %]
#           [% u.projects.0.name %]
#         [% END %]
}

sub show_reviewer {
  my $self = shift;

  return ($self->{obj}->is_reviewer)? "<span class=\"badge text-bg-success\">Reviewer</span>" : '';
}

sub show_advanced {
  my $self = shift;

  return ($self->{obj}->is_advanced)? "<span class=\"badge text-bg-primary\">Advanced</span>" : '';
}

sub show_expert {
  my $self = shift;

  return ($self->{obj}->is_expert)? "<span class=\"badge text-bg-warning\">Expert</span>" : '';
}

sub show_admin {
  my $self = shift;

  return ($self->{obj}->is_admin)? "<span class=\"badge text-bg-danger\">Admin</span>" : '';
}

sub show_expires {
  my $self = shift;

  return '' unless $self->{obj}->{active};
  return '' if $self->{obj}->{internal};
  my $ht_user = $self->{obj}->ht_user;
  return '' unless defined $ht_user and defined $ht_user->{expires};
  my $diff = Utilities->new->Timediff($ht_user->{expires});
  # FIXME: format based on expired or not.
#   [% IF u.expiration.days.defined && u.expiration.days <= 30 %]
#     <img width="20" height="20" alt="Warning: expires within 30 days"
#          src="[% warn %]"/>
#   [% END %]
  my $html = Utilities->new->FormatDate($ht_user->{expires});
  if ($diff <= 0.0) {
    # Expired
    $html .= "&nbsp;<span class=\"badge text-bg-danger\">Expired</span>";
  } elsif ($diff <= 30.0) {
    $html .= "&nbsp;<span class=\"badge text-bg-warning\">Expiring Soon</span>";
  }
  return $html;
}

# sub __check_mark {
#   my $self = shift;
# 
#   return "<span class=\"badge bg-success\">\N{U+25CF}</span>";
# }


sub edit_institution {
  my $self = shift;

  my $html = '<select id="institution" class="select-institution" name="user[institution]">' . "\n";
  foreach my $institution (@{Institution::All()}) {
    $html .= "<option value='$institution->{inst_id}'";
    $html .= ' selected' if $self->{obj}->{institution} eq $institution->{inst_id};
    $html .= '>';
    $html .= Utilities->new->EscapeHTML($institution->{name});
    $html .= "</option>\n";
  }
  $html .= "</select>\n";
  return $html;
}

sub edit_note {
  my $self = shift;

  return "<textarea rows=\"3\" cols=\"20\">$self->{obj}->{note}</textarea>\n";
}

1;
