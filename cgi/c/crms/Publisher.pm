package Publisher;

use strict;
use warnings;
use vars qw( @ISA @EXPORT @EXPORT_OK );
our @EXPORT = qw(GetPublisherDataRef PublisherDataSearchMenu);

my @FieldNames = ('NF/F','Name','City State','Email','Phone','Postal',
                  'Added','Notes','Notes 2', 'Reviewed');
my @Fields     = qw(nff name citystate email phone postal added notes1 notes2 reviewed);

sub GetPublisherDataRef
{
  my $self         = shift;
  my $order        = shift;
  my $dir          = shift;
  my $search1      = shift;
  my $search1Value = shift;
  my $op1          = shift;
  my $search2      = shift;
  my $search2Value = shift;
  my $startDate    = shift;
  my $endDate      = shift;
  my $offset       = shift;
  my $pagesize     = shift;
  my $download     = shift;
  #print("GetQueueRef('$order','$dir','$search1','$search1Value','$op1','$search2','$search2Value','$startDate','$endDate','$offset','$pagesize','$download');<br/>\n");
  
  $pagesize = 20 unless $pagesize and $pagesize > 0;
  $offset = 0 unless $offset and $offset > 0;
  $order = 'name' unless $order;
  $offset = 0 unless $offset;
  #$search1 = ConvertToSearchTerm($search1);
  #$search2 = ConvertToSearchTerm($search2);
  my @rest = ();
  my $tester1 = '=';
  my $tester2 = '=';
  if ($search1Value =~ m/.*\*.*/)
  {
    $search1Value =~ s/\*/%/gs;
    $tester1 = ' LIKE ';
  }
  if ($search2Value =~ m/.*\*.*/)
  {
    $search2Value =~ s/\*/%/gs;
    $tester2 = ' LIKE ';
  }
  if ($search1Value =~ m/([<>!]=?)\s*(\d+)\s*/)
  {
    $search1Value = $2;
    $tester1 = $1;
  }
  if ($search2Value =~ m/([<>!]=?)\s*(\d+)\s*/)
  {
    $search2Value = $2;
    $tester2 = $1;
  }
  push @rest, "added >= '$startDate'" if $startDate;
  push @rest, "added <= '$endDate'" if $endDate;
  if ($search1Value ne '' && $search2Value ne '')
  {
    push @rest, "($search1 $tester1 '$search1Value' $op1 $search2 $tester2 '$search2Value')";
  }
  else
  {
    push @rest, "$search1 $tester1 '$search1Value'" if $search1Value ne '';
    push @rest, "$search2 $tester2 '$search2Value'" if $search2Value ne '';
  }
  my $restrict = ((scalar @rest)? 'WHERE ':'') . join(' AND ', @rest);
  my $sql = "SELECT COUNT(*) FROM publishers $restrict\n";
  #print "$sql<br/>\n";
  my $totalVolumes = $self->SimpleSqlGet($sql);
  $offset = $totalVolumes-($totalVolumes % $pagesize) if $offset >= $totalVolumes;
  my $limit = ($download)? '':"LIMIT $offset, $pagesize";
  my @return = ();
  $sql = 'SELECT nff,name,citystate,email,phone,postal,added,notes1,notes2,reviewed' .
         " FROM publishers $restrict ORDER BY $order $dir $limit";
  #print "$sql<br/>\n";
  my $ref = undef;
  eval {
    $ref = $self->GetDb()->selectall_arrayref($sql);
  };
  if ($@)
  {
    $self->SetError($@);
  }
  my $data = join "\t", @FieldNames;
  foreach my $row (@{$ref})
  {
    my %item = ();
    $item{$Fields[$_]} = $row->[$_] for (0 ... 9);
    $item{'added'} = '' if $item{'added'} eq '0000-00-00';
    push @return, \%item;
    if ($download)
    {
      $data .= "\n" . join "\t", @{$row};
    }
  }
  if (!$download)
  {
    my $n = POSIX::ceil($offset/$pagesize+1);
    my $of = POSIX::ceil($totalVolumes/$pagesize);
    $n = 0 if $of == 0;
    $data = {'rows' => \@return,
             'volumes' => $totalVolumes,
             'page' => $n,
             'of' => $of
            };
  }
  return $data;
}

# Generates HTML to get the field type menu on the Publisher Data page.
sub PublisherDataSearchMenu
{
  my $self = shift;
  my $searchName = shift;
  my $searchVal = shift;
  
  my $html = "<select title='Search Field' name='$searchName' id='$searchName'>\n";
  foreach my $i (0 .. scalar @Fields - 1)
  {
    $html .= sprintf("  <option value='%s'%s>%s</option>\n",
                     $Fields[$i], ($searchVal eq $Fields[$i])? ' selected="selected"':'',
                     $FieldNames[$i]);
  }
  $html .= "</select>\n";
  return $html;
}

1;
