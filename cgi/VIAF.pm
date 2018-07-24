package VIAF;
use JSON::XS;
use Unicode::Normalize;
use URI::Escape;

# If successful, returns a hash ref that contains values for some subset of
# the following keys: 'abd', 'add', 'author' (the VIAF author name), and 'country'.
# Also has a 'url' field for debugging bad URLs or unparseable responses.
# Has an 'error' field in case of comms error.
# Returns undef if none of that data could be found.
sub GetVIAFData
{
  my $self   = shift;
  my $author = shift;

  my $ret;
  return unless defined $author and length $author;
  my $decomposed = Unicode::Normalize::decompose($author);
  my $sql = 'SELECT viaf_author,abd,`add`,country,viafID,IF(time<=DATE_SUB(NOW(),INTERVAL 1 MONTH),1,0)'.
            ' FROM viaf WHERE author=?';
  my $ref = $self->SelectAll($sql, $author);
  if (defined $ref && scalar @{$ref} > 0)
  {
    # If the data is over a month old, re-fetch.
    my $old = $ref->[0]->[5];
    if ($old)
    {
      $self->PrepareSubmitSql('DELETE FROM viaf WHERE author=?', $a);
    }
    else
    {
      return {'author' => $ref->[0]->[0],
              'abd' => $ref->[0]->[1], 'add' => $ref->[0]->[2],
              'country' => $ref->[0]->[3], 'viafID' => $ref->[0]->[4]};
    }
  }
  $author =~ s/["#]//g;
  my $url = 'http://viaf.org/viaf/search?query=local.personalNames+all+%22'.
            $author.
            '%22+&maximumRecords=10&startRecord=1&sortKeys=holdingscount&'.
            'httpAccept=application/json';
  my $ua = LWP::UserAgent->new;
  $ua->timeout(10);
  my $req = HTTP::Request->new(GET => $url);
  my $res = $ua->request($req);
  if (!$res->is_success)
  {
    return {'error' => $res->code(), 'url' => $url};
  }
  my $jsonxs = JSON::XS->new->utf8;
  my $json;
  eval {
    no warnings 'all';
    $json = $jsonxs->decode($res->content);
  };
  if ($@)
  {
    $self->Note('VIAF parse error for '. $url);
    return {'error' => 'VIAF parse error', 'url' => $url};
  }
  my $records = $json->{'searchRetrieveResponse'}->{'records'};
  next unless defined $records;
  my $n = 1;
  my $of = scalar @{$records};
  my $best;
  foreach my $record (@{$records})
  {
    my $rec = ExtractVIAFAuthorData($decomposed, $record->{'record'}->{'recordData'});
    if (defined $rec)
    {
      if ($rec->{'quality'} == 1)
      {
        $ret = $rec;
        last;
      }
      else
      {
        $best = $rec;
      }
    }
    $n++;
  }
  $ret = $best unless defined $ret;
  if (defined $ret)
  {
    $sql = 'DELETE FROM viaf WHERE author=?';
    $self->PrepareSubmitSql($sql, $author);
    $sql = 'INSERT INTO viaf (author,viaf_author,abd,`add`,country,viafID) VALUES (?,?,?,?,?,?)';
    $self->PrepareSubmitSql($sql, $author, $ret->{'author'}, $ret->{'abd'},
                            $ret->{'add'}, $ret->{'country'}, $ret->{'viafID'});
  }
  $ret->{'url'} = $url;
  return $ret;
}

# Author should be already decomposed.
# Attempts to pull a viable match from VIAF recordData element
# using mainHeadings and x400 values.
# FIXME: should find a way to signal a US record was found so caller can bail out.
sub ExtractVIAFAuthorData
{
  my $author = shift;
  my $record = shift;

  my $ret;
  my $best;
  my $q;
  my ($normalized, $normalizedt, $normalizednn) = VIAFNormalize($author);
  my $data = $record->{'mainHeadings'}->{'data'};
  $data = [$data] if ref $data eq 'HASH';
  foreach my $datum (@{$data})
  {
    my $author2 = Unicode::Normalize::decompose($datum->{'text'});
    my ($normalized2, $normalized2t, $normalized2nn) = VIAFNormalize($author2);
    if ($normalized eq $normalized2)
    {
      $ret = {'author' => $author2};
      last;
    }
    if ($normalizedt eq $normalized2t)
    {
      $ret = {'author' => $author2};
      last;
    }
    if ($normalizednn eq $normalized2nn)
    {
      $best = {'author' => $author2};
    }
  }
  if (!defined $ret)
  {
    my $data = $record->{'x400s'}->{'x400'};
    $data = [$data] if ref $data eq 'HASH';
    foreach my $datum (@{$data})
    {
      my $author2 = Unicode::Normalize::decompose($datum->{'datafield'}->{'normalized'});
      my ($normalized2, $normalized2t, $normalized2nn) = VIAFNormalize($author2);
      if ($normalized eq $normalized2)
      {
        $ret = {'author' => $author2};
        last;
      }
      if ($normalizedt eq $normalized2t)
      {
        $ret = {'author' => $author2};
        last;
      }
      if ($normalizednn eq $normalized2nn)
      {
        $best = {'author' => $author2};
      }
    }
  }
  $ret = $best unless defined $ret;
  return unless defined $ret;
  # Extract dates from record if possible. VIAF has 0 = no data.
  # Format may be bare year or YYY(Y)-MM-DD.
  if ($record->{'dateType'} eq 'lived')
  {
    my $date = $record->{'birthDate'};
    my @parts = split '-', $date;
    $ret->{'abd'} = $parts[0] if $parts[0] and $parts[0] =~ m/^\d+$/;
    $date = $record->{'deathDate'};
    @parts = split '-', $date;
    $ret->{'add'} = $parts[0] if $parts[0] and $parts[0] =~ m/^\d+$/;
  }
  # Fall back to extracting dates our record or VIAF's if not explicit.
  if (!$ret->{'abd'} || !$ret->{'add'})
  {
    my ($abd, $add) = ExtractAuthorDates($author);
  }
  $data = $record->{'nationalityOfEntity'}->{'data'};
  $data = [$data] if ref $data eq 'HASH';
  my @countries;
  my $gotUS;
  foreach my $datum (@{$data})
  {
    my $country = $datum->{'text'};
    $country = 'US' if $country =~ m/^[a-z][a-z]u$/ or $country eq 'U.S';
    $country = 'GB' if $country =~ m/^[a-z][a-z]k$/;
    $gotUS = 1 if $country eq 'US';
    push @countries, $country if $country ne 'US';
  }
  push @countries, 'US' if $gotUS and 0 == scalar @countries;
  return unless scalar @countries;
  $ret->{'country'} = $countries[0];
  $ret->{'viafID'} = $record->{'viafID'};
  $ret->{'quality'} = (defined $best && $ret == $best)? 0:1;
  return $ret;
}

sub ExtractAuthorDates
{
  my $author = shift;

  my ($abd, $add);
  return (undef, undef) unless defined $author;
  my $regex = '(ca\.\s*)?((\d?\d\d\d)\??)?\s*-\s*(ca\.\s*)?((\d?\d\d\d)\??)?[.,;) ]*$';
  if ($author =~ m/$regex/)
  {
    $abd = $3;
    $add = $6;
    ($abd, $add) = (undef, undef) if $author =~ m/(fl\.*|active)\s*$regex/i;
  }
  if (!defined $abd || !defined $abd)
  {
    $regex = '\sb\.\s*((\d?\d\d\d)\??)[.,;) ]*$';
    $abd = $2 if $author =~ m/$regex/;
    $regex = '\sd\.\s*((\d?\d\d\d)\??)[.,;) ]*$';
    $abd = $2 if $author =~ m/$regex/;
  }
  return ($abd, $add);
}

# Returns a trio of normalized author strings, the first with digits preserved,
# the second with death date (if any) truncated, and the third with digits removed.
sub VIAFNormalize
{
  my $author = shift;

  my $n1 = $author;
  # Translate b. XXXX into XXXX-, ca. XXXX into ca.XXXX
  $n1 =~ s/\s+b\.\s+(\d\d\d\d?)/ $1-/;
  $n1 =~ s/(\s+ca\.)\s+(\d\d\d\d?)/$1$2/;
  # Normalize spacing convention between initials and years
  $n1 =~ s/\./ /g;
  $n1 =~ s/(\d\d\d\d?\??)-((ca\.\s*)?\d\d\d\d?)/$1 $2/;
  $n1 = lc $n1;
  my $n3 = $n1;
  my $normalizer = '[^A-Za-z0-9 ]';
  my $normalizernn = '[^A-Za-z ]';
  $n1 =~ s/$normalizer//g;
  $n3 =~ s/$normalizernn//g;
  $n1 =~ s/\s+/ /g;
  $n1 =~ s/\s+$//;
  $n3 =~ s/\s+/ /g;
  $n3 =~ s/\s+$//;
  my $n2 = $n1;
  $n2 = substr $n2, 0, -5 if $n2 =~ m/\d\d\d\d\s\d\d\d\d$/;
  return ($n1, $n2, $n3);
}

sub VIAFLink
{
  my $self   = shift;
  my $author = shift;

  $author = URI::Escape::uri_escape_utf8($author);
  'https://viaf.org/viaf/search?query=local.personalNames+all+%22'.
  $author. '%22&stylesheet=/viaf/xsl/results.xsl&sortKeys=holdingscount';
}

return 1;
