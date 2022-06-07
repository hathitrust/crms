package CRMS::Queue;

use strict;
use warnings;
use utf8;
#use 5.010;

use Carp;
use Data::Dumper;
use List::Util;
use POSIX;

use CRMS::DB;
use Utilities;

# FIXME: make this return array of Queue objects instead of plain old hashes.
# queue index can call presenter->set_object and then render each in turn.
sub Search {
  my %params = @_;
  my @debug = (sprintf("Params %s", Dumper \%params));
  my $page_size = $params{page_size} || 20;
  my $page = $params{page} || 1;
  my $dir = $params{dir} || 'ASC';
  
  my $search1_value = $params{search1_value} || '';
  my $op1 = $params{op1} || 'AND';
  my $search2_value = $params{search2_value} || '';
  my $order = ConvertToSearchTerm($params{order}, 1);
  my $start_date = $params{start_date};
  my $end_date = $params{end_date};
  my @clauses;
  my @params;
  if ($search1_value ne '') {
    my $search1 = ConvertToSearchTerm($params{search1});
    my $tester1 = '=';
    if ($search1_value =~ m/\*/) {
      $search1_value =~ s/\*/%/gs;
      $tester1 = ' LIKE ';
    }
    elsif ($search1_value =~ m/([<>!]=?)\s*(\d+)\s*/) {
      $search1_value = $2;
      $tester1 = $1;
    }
    push @clauses, "$search1 $tester1 ?";
    push @params, $search1_value;
  }
  if ($search2_value ne '') {
    my $search2 = ConvertToSearchTerm($params{search2});
    my $tester2 = '=';
    if ($search2_value =~ m/\*/) {
      $search2_value =~ s/\*/%/gs;
      $tester2 = ' LIKE ';
    }
    elsif ($search2_value =~ m/([<>!]=?)\s*(\d+)\s*/) {
      $search2_value = $2;
      $tester2 = $1;
    }
    push @clauses, "$search2 $tester2 ?";
    push @params, $search2_value;
  }
  if ($op1 eq 'OR') {
    @clauses = '(' . $clauses[0] . ' OR ' . $clauses[1] . ')';
  }
  if ($start_date) {
    push @clauses, 'q.time>=?';
    push @params, $start_date;
  }
  if ($end_date) {
    push @clauses, 'q.time<=?';
    push @params, $end_date;
  }
  # FIXME: deal with OR
  # if ($search1_value ne '' && $search2_value ne '') {
#     push @rest, "($search1 $tester1 '$search1_value' $op1 $search2 $tester2 '$search2_value')";
#   } else {
#     push @rest, "$search1 $tester1 '$search1_value'" if $search1_value ne '';
#     push @rest, "$search2 $tester2 '$search2_value'" if $search2_value ne '';
#   }
  my $restrict = ((scalar @clauses)? 'WHERE ' : '') . join(' AND ', @clauses);
  my $sql_from = ' FROM queue q'.
                 ' LEFT JOIN bibdata b ON q.id=b.id'.
                 ' INNER JOIN projects p ON q.project=p.id '.
                 ' LEFT JOIN users locked_u ON q.locked=locked_u.id'.
                 ' LEFT JOIN users added_by_u ON q.added_by=added_by_u.id '.
                 $restrict;
  my $sql = 'SELECT COUNT(*)' . $sql_from;
  push @debug, $sql;
  my $ref;
  eval {
    $ref = CRMS::DB->new->dbh->selectall_arrayref($sql, undef, @params);
  };
  if ($@) {
    Carp::confess("SQL failed ($sql): $@");
  }
  my $row_count = $ref->[0]->[0];
  my $offset = ($page - 1) * $page_size;
  my @return = ();
  $sql = 'SELECT q.id,DATE(q.time),q.status,locked_u.email,YEAR(b.pub_date),q.priority,'.
         'b.title,b.author,b.country,p.name,q.source,q.ticket,added_by_u.email'.
         $sql_from .
         ' ORDER BY '. "$order $dir LIMIT $offset, $page_size";
  push @debug, $sql;
  eval {
    $ref = CRMS::DB->new->dbh->selectall_arrayref($sql, undef, @params);
  };
  if ($@) {
    Carp::confess("SQL failed ($sql): $@");
  }
  my $data;
  foreach my $row (@{$ref}) {
    my $id = $row->[0];
    $sql = 'SELECT COUNT(*) FROM reviews WHERE id=?';
    #my $reviews = $self->SimpleSqlGet($sql, $id);
    eval {
      $ref = CRMS::DB->new->dbh->selectall_arrayref($sql);
    };
    if ($@) {
      Carp::confess("SQL failed ($sql): $@");
    }
    my $reviews = $ref->[0]->[0];
    $sql = 'SELECT COUNT(*) FROM reviews WHERE id=? AND hold=1';
    #my $holds = $self->SimpleSqlGet($sql, $id);
    eval {
      $ref = CRMS::DB->new->dbh->selectall_arrayref($sql);
    };
    if ($@) {
      Carp::confess("SQL failed ($sql): $@");
    }
    my $holds = $ref->[0]->[0];
    $sql = 'SELECT COUNT(*) FROM reviews r INNER JOIN users u ON r.user=u.id'.
           ' WHERE r.id=? AND u.expert=1';
    #my $expert_reviews = $self->SimpleSqlGet($sql, $id);
    eval {
      $ref = CRMS::DB->new->dbh->selectall_arrayref($sql);
    };
    if ($@) {
      Carp::confess("SQL failed ($sql): $@");
    }
    my $expert_reviews = $ref->[0]->[0];
    my $item = {
      id       => $id,
      date     => $row->[1],
      status   => $row->[2],
      locked   => $row->[3],
      pub_date  => $row->[4],
      priority => Utilities::new->StripDecimal($row->[5]), # FIXME: should go in presenter
      expert_reviews => $expert_reviews,
      title    => $row->[6],
      author   => $row->[7],
      country  => $row->[8],
      reviews  => $reviews,
      holds    => $holds,
      project  => $row->[9],
      source   => $row->[10],
      ticket   => $row->[11],
      added_by => $row->[12]
     };
    push @return, $item;
  }
  my $page_count = POSIX::ceil($row_count / $page_size);
  my $first_row = (($page - 1) * $page_size) + 1;
  my $last_row = List::Util::min($row_count, $first_row + $page_size - 1);
  return {
    'rows' => \@return,
    'row_count' => $row_count,
    'page' => $page,
    'page_size' => $page_size,
    'page_count' => $page_count,
    'first_row' => $first_row,
    'last_row' => $last_row,
    'debug' => join("\n", @debug)
  };
}

sub ConvertToSearchTerm {
  my $search = shift;
  my $order  = shift; # Orders by time and not simply date, may be excessively anal-retentive

  if (!$search || $search eq 'id') {
    return 'q.id';
  }
  my $new_search;
  if ($search eq 'date') {
    $new_search = 'q.time';
    $new_search = 'DATE(q.time)' unless $order;
  }
  elsif ($search eq 'user') { $new_search = 'u.id'; }
  elsif ($search eq 'status') { $new_search = 'q.status'; }
  elsif ($search eq 'title') { $new_search = 'b.title'; }
  elsif ($search eq 'author') { $new_search = 'b.author'; }
  elsif ($search eq 'country') { $new_search = 'b.country'; }
  elsif ($search eq 'priority') { $new_search = 'q.priority'; }
  elsif ($search eq 'pub_date') { $new_search = 'YEAR(b.pub_date)'; }
  elsif ($search eq 'locked') { $new_search = 'locked_u.email'; }
  elsif ($search eq 'expert_reviews') {
    $new_search = '(SELECT COUNT(*) FROM reviews r INNER JOIN users u'.
                  ' ON r.user=u.id WHERE r.id=q.id AND u.expert=1)';
  }
  elsif ($search eq 'reviews') {
    $new_search = '(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id)';
  }
  elsif ($search eq 'cid') { $new_search = 'b.sysid'; }
  elsif ($search eq 'holds') {
    $new_search = '(SELECT COUNT(*) FROM reviews r WHERE r.id=q.id AND r.hold=1)';
  }
  elsif ($search eq 'source') {
    $new_search = 'q.source';
  }
  elsif ($search eq 'project') { $new_search = 'p.name'; }
  elsif ($search eq 'added_by') { $new_search = 'added_by_u.email'; }
  elsif ($search eq 'ticket') { $new_search = 'q.ticket'; }
  Carp::confess("Unknown queue search term '$search'") unless defined $new_search;
  return $new_search;
}

sub Find {
  my $id = shift;

  Carp::confess "Queue::Find undefined id" unless defined $id;

  my $sql = 'SELECT * FROM queue WHERE id=?';
  my $ref = CRMS::DB->new->dbh->selectall_hashref($sql, 'id', undef, $id);
  my $queue = __queue_from_hashref($ref);
  return (scalar @$queue)? $queue->[0] : undef;
}

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{$_} = $args{$_} for keys %args;
  return $self;
}

sub __queue_from_hashref {
  my $hashref = shift;

  my @queue;
  push @queue, new Queue(%{$hashref->{$_}}, 'persisted', 1) for keys %$hashref;
  return \@queue;
}

1;
