#!/l/local/bin/perl

my $DLXSROOT;
my $DLPS_DEV;
BEGIN 
{ 
  $DLXSROOT = $ENV{'DLXSROOT'}; 
  $DLPS_DEV = $ENV{'DLPS_DEV'}; 
  unshift ( @INC, $ENV{'DLXSROOT'} . "/cgi/c/crms/" );
}

use strict;
use CRMS;
use Getopt::Long;
use Spreadsheet::WriteExcel;
use Encode;

my $usage = <<END;
USAGE: $0 [-ahiprv] [-n N] [-t TYPE] [-s VOL_ID [-s VOL_ID2...]]
          [-m MAIL_ADDR [-m MAIL_ADDR2...]] [SOURCE_FILE]

Creates a report of recent exports for the orphan works project.

-a         Ignore the -n flag and export all.
-h         Print this help message.
-i         Insert the volumes into the orphan table.
-m ADDR    Mail the report to ADDR. May be repeated for multiple addresses.
-n N       Export no more than N volumes. (Default is 3000.)
-p         Run in production.
-r         Re-report on all volumes in the orphan table. (Ignore -a and -n flags.)
-s VOL_ID  Report only for HT volume VOL_ID. May be repeated for multiple volumes.
-t TYPE    Print a report of TYPE where TYPE={html,none,tsv,excel}.
           In the case of excel it will be created in place and
           attached to any outgoing mail. Default is excel.
-v         Be verbose. May be repeated.
END
my $all;
my $help;
my $insert;
my @mails;
my $n;
my $production;
my $rereport;
my @singles;
my $type = 'excel';
my $verbose;
my $file = undef;
my $fh = undef;

Getopt::Long::Configure ('bundling');
die 'Terminating' unless GetOptions('a' => \$all,
           'h|?' => \$help,
           'i' => \$insert,
           'm:s@' => \@mails,
           'n:s' => \$n,
           'p' => \$production,
           'r' => \$rereport,
           's:s@' => \@singles,
           't:s' => \$type,
           'v+' => \$verbose);
$DLPS_DEV = undef if $production;
print "Verbosity $verbose\n" if $verbose;
die "$usage\n\n" if $help;
if (scalar @ARGV)
{
  $file = $ARGV[0];
  open $fh, $file or die "failed to open $file: $@ \n";
  $rereport = undef;
}
my $configFile = "$DLXSROOT/bin/c/crms/crms.cfg";
my $crms = CRMS->new(
    logFile      =>   "$DLXSROOT/prep/c/crms/orph_hist.txt",
    configFile   =>   $configFile,
    verbose      =>   $verbose,
    root         =>   $DLXSROOT,
    dev          =>   $DLPS_DEV
);

$crms->set('ping','yes');
require $configFile;
my %metaissues = ();
my %types = ('html'=>1,'none'=>1,'tsv'=>1,'excel'=>1);
die "Bad value '$type' for -t flag" unless defined $types{$type};
my $dbh = $crms->GetDb();
$n = 3000 unless $n and $n > 0;
my $ref = undef;
if ($fh)
{
  $ref = GetDataFromFile($fh);
}
else
{
  my $sql = "SELECT id,gid FROM exportdata WHERE attr='ic' AND reason='ren'";
  if (@singles && scalar @singles)
  {
    #$sql = sprintf("SELECT id,gid,attr,reason FROM exportdata WHERE attr='ic' AND id in ('%s')", join "','", @singles);
    $sql = sprintf("SELECT id,gid,attr,reason FROM exportdata WHERE id in ('%s')", join "','", @singles);
  }
  $sql .= ' AND src!="inherited" AND id NOT IN (SELECT id FROM orphan)';
  $sql = 'SELECT id FROM orphan WHERE id IN (SELECT id FROM exportdata)' if $rereport;
  $sql .= ' ORDER BY time DESC';
  print "$sql\n" if $verbose > 1;
  $ref = $dbh->selectall_arrayref($sql);
}
my $now = $crms->SimpleSqlGet("SELECT DATE(NOW())");
my $txt = '';
my $title = "CRMS Orphan Works Report $now";
my ($workbook,$worksheet);
my $excelpath = sprintf('/l1/prep/c/crms/OrphanCand_%s.xls', $now);
my @cols= ('#', 'HT ID','attr','reason','Renewal #','Renewal Date','Title','Author Last Name','Author First Name','Author Dates',
           'Publisher 1 Location','Publisher 1 Name','Publisher 1 Year',
           'Publisher 2 Location','Publisher 2 Name','Publisher 2 Year',
           'Publisher 3 Location','Publisher 3 Name','Publisher 3 Year',
           'Publisher 4 Location','Publisher 4 Name','Publisher 4 Year',
           'Country of Publication');
my $sortIdx = 10; # For sorting on pub 1 name (# is prepended after the sort)
my $sort2Idx = -1;
if ($fh)
{
  $sortIdx = 21;
  $sort2Idx = 10;
}
if ($type eq 'html')
{
  $txt .= '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">' . "\n";
  $txt .= '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head>' .
        "<meta http-equiv='Content-Type' content='text/html; charset=utf-8'/>\n" .
        "<title>$title</title>\n" .
        '</head><body><table border="1"><tr><th>' . join('</th><th>', @cols) . "</th></tr>\n";
}
elsif ($type eq 'tsv')
{
  $txt .= join("\t", @cols) . "\n";
}
elsif ($type eq 'excel')
{
  $workbook  = Spreadsheet::WriteExcel->new($excelpath);
  $worksheet = $workbook->add_worksheet();
  $worksheet->write_string(0, $_, $cols[$_]) for (0 .. scalar @cols);
}
my $found = 0;
my %seen = ();
$n = scalar @{$ref} if $all || $rereport;
printf "%d volumes found, $n sought\n", scalar @{$ref} if $verbose;
my @rows = ();
foreach my $row (@{$ref})
{
  my $id = $row->[0];
  my $gid;
  
  if ($rereport)
  {
    my $sql = "SELECT gid FROM exportdata WHERE id='$id' ORDER BY time DESC LIMIT 1";
    $gid = $crms->SimpleSqlGet($sql);
  }
  else
  {
    $gid = $row->[1];
  }
  print "Record: $id ($gid)\n" if $verbose;
  if ($seen{$id})
  {
    print "Already saw $id\n";
    next;
  }
  next if $fh and $crms->SimpleSqlGet("SELECT COUNT(*) FROM orphan WHERE id='$id'");
  my $sql = 'SELECT r.renNum,r.renDate FROM historicalreviews r INNER JOIN users u ON r.user=u.id ' .
            "WHERE r.gid=$gid AND r.renNum IS NOT NULL AND r.renDate IS NOT NULL " .
            'ORDER BY u.reviewer+(2*u.advanced)+(4*u.expert)+(8*u.admin)+(16*u.superadmin) DESC LIMIT 1';
  my $ref2 = $dbh->selectall_arrayref($sql);
  printf "$sql; %d results\n", scalar @{$ref2} if $verbose > 1;
  #next unless $ref2 && scalar @{$ref2};
  my ($attr,$reason,$src,$usr,$time,$note) = @{$crms->RightsQuery($id,1)->[0]};
  if ($attr ne 'ic' && !$rereport && !$fh)
  {
    print "Next 1\n";
    next;
  }
  my $sysid = $crms->BarcodeToId($id);
  my $record = $crms->GetMetadata($sysid);
  if (!$sysid || !$record)
  {
    #print "Cannot get metadata for $id\n";
    $crms->ClearErrors();
    $metaissues{$id} = 1;
    next;
  }
  $seen{$id} = 1;
  $found++;
  printf "Found: $found of %s\n", ($all)?'all':$n if $verbose;
  my ($renNum,$renDate) = ('','');
  ($renNum,$renDate) = @{$ref2->[0]} if $ref2 && scalar @{$ref2};
  my $author = $crms->GetRecordAuthor($id, $record);
  my ($authlast,$authrest) = split m/,\s*/, $author, 2;
  my $title = $crms->GetRecordTitle($id, $record);
  my $dates = GetRecordAuthorDates($id, $record);
  my @fields = ($id, $attr, $reason, $renNum, $renDate, $title, $authlast, $authrest, $dates);
  my @pubs = (['','',''],['','',''],['','',''],['','','']);
  my $pubn = 0;
  my $nodes = $record->findnodes("//*[local-name()='datafield' and \@tag='260']/*[local-name()='subfield']");
  my $code = '';
  my $lastcode = undef;
  my %h = ('a'=>0,'b'=>1,'c'=>2);
  foreach my $node ($nodes->get_nodelist())
  {
    printf "Doing a subfield: $node (%s)\n", $node->localname if $verbose > 2;
    my $code = lc $node->getAttribute('code');
    my $field = $node->textContent();
    $field =~ s/[,\.]+\s*$// if $code eq 'c';
    print "Field: '$field' for '$code'\n" if $verbose > 1;
    # If we are seeing a code same as or less than the one we last saw, advance.
    $pubn++ if $lastcode and $code le $lastcode;
    last if $pubn == 5;
    $pubs[$pubn]->[$h{$code}] = $field;
    #printf "pubs[$pubn]->%s = '$field' from '$code'\n", $h{$code};
    $lastcode = $code;
    #print "pubn $pubn, code $code, lastcode $lastcode\n";
  }
  push @fields, @{$pubs[$_]} for (0 .. 3);
  printf "Have %d pubs, %d fields\n", scalar @pubs, scalar @fields if $verbose > 1;
  push @fields, GetCountry($id, $record);
  push @rows, join '____', @fields;
  $crms->PrepareSubmitSql("INSERT INTO orphan (id) VALUES ('$id')") if $insert and !$rereport;
  if ($found >= $n and !$all and !$rereport)
  {
    print "I'm done! found $found n $n all $all rereport $rereport\n" if $verbose;
    last;
  }
  
}
$found = 0;
foreach my $row (SortByPub(\@rows))
{
  my @fields = split m/____/, $row;
  $found++;
  unshift @fields, $found;
  if ($type eq 'html')
  {
    $txt .= sprintf("<tr><td>%s</td></tr>\n", join '</td><td>', map {s/&/&amp;/g;$_;} @fields);
  }
  elsif ($type eq 'tsv')
  {
    $txt .= join "\t", @fields;
    #$txt .= join "\t", map {s/\s+/ /g;$_;} @fields;
    $txt .= "\n";
  }
  elsif ($type eq 'excel')
  {
    $worksheet->write_string($found, $_, $fields[$_]) for (0 .. scalar @fields);
  }
}
if ($type eq 'html')
{
  $txt .= "</table></body></html>\n\n";
}
$workbook->close() if $type eq 'excel';

if (@mails)
{
  use Mail::Sender;
  $title = 'Dev: ' . $title if $DLPS_DEV;
  my $sender = new Mail::Sender { smtp => 'mail.umdl.umich.edu',
                                  from => $CRMSGlobals::adminEmail,
                                  on_errors => 'undef' }
    or die "Error in mailing : $Mail::Sender::Error\n";
  my $to = join ',', @mails;
  my $ctype = ($type eq 'html')? 'text/html':'text/plain';
  $sender->OpenMultipart({
    to => $to,
    subject => $title,
    ctype => $ctype,
    encoding => 'utf-8'
    }) or die $Mail::Sender::Error,"\n";
  $sender->Body();
  if ($type eq 'excel')
  {
    $txt = "Attached please find $found volumes to be considered for the Orphan Works Project.\n"; 
  }
  my $bytes = encode('utf8', $txt);
  $sender->SendEnc($bytes);
  if ($type eq 'excel')
  {
    $sender->Attach({
      description => 'Orphan Report',
      ctype => 'application/vnd.ms-excel',
      encoding => 'Base64',
      disposition => 'attachment; filename=*',
      file => $excelpath
      });
  }
  $sender->Close();
}
else
{
  print $txt;
}
print "Could not get metadata for $_\n" for sort keys %metaissues;
print "Warning: $_\n" for @{$crms->GetErrors()};

close $fh if $fh;

# array ref of arrayrefs (id,gid)
sub GetDataFromFile
{
  my $fh = shift;

  my @data = ();
  foreach my $sysid (<$fh>)
  {
    chomp $sysid;
    next if $sysid =~ m/^\s*$/;
    #my $record = $crms->GetMetadata($sysid);
    my $rows = $crms->VolumeIDsQuery($sysid);
    my ($id2,$chron,$rights) = split '__', $rows->[0];
    push @data, [$id2,0];
    print "Got $id2 for $sysid\n" if $verbose;
  }
  my @arr = SortByRand(\@data);
  return \@arr;
}

sub GetRecordAuthorDates
{
  my $id     = shift;
  my $record = shift;

  my $data = $crms->GetMarcDatafield($id,'100','d',$record);
  $data = $crms->GetMarcDatafield($id,'700','d',$record) unless $data;
  my $len = length $data;
  if ($len && $len % 3 == 0)
  {
    my $s = $len / 3;
    my $f1 = substr $data, 0, $s;
    my $f2 = substr $data, $s, $s;
    my $f3 = substr $data, 2*$s, $s;
    #print "'$f1' + '$f2' + '$f3' from '$data' ($id)\n";
    $data = $f1 if $f1 eq $f2 and $f2 eq $f3;
  }
  $data =~ s/[\.,:;]\s*$//;
  return $data;
}

sub SortByRand
{
  my $ref = shift;

  return sort {
    (rand() < 0.5)? $a->[0] cmp $b->[0]:$b->[0] cmp $a->[0];
  } @{$ref};
}

sub SortByPub
{
  my $ref = shift;

  return sort {
    my @aar = split m/____/, $a;
    my @bar = split m/____/, $b;
    my $aa = lc $aar[$sortIdx];
    my $ba = lc $bar[$sortIdx];
    my $ret = $aa cmp $ba;
    if ($sort2Idx >= 0 && !$ret)
    {
      my $ab = lc $aar[$sort2Idx];
      my $bb = lc $bar[$sort2Idx];
      $ret = $ab cmp $bb;
    }
    return $ret;
  } @{$ref};
}

sub GetCountry
{
  my $id     = shift;
  my $record = shift;
  
my %countries = ('aa' => 'Albania',
'abc' => 'Canada (Alberta)',
'ac' => 'Ashmore and Cartier Islands',
'aca' => 'Australian Capital Territory',
'ae' => 'Algeria',
'af' => 'Afghanistan',
'ag' => 'Argentina',
'ai' => 'Anguilla',
'ai' => 'Armenia (Republic)',
'air' => 'Armenian S.S.R.',
'aj' => 'Azerbaijan',
'ajr' => 'Azerbaijan S.S.R.',
'aku' => 'USA (Alaska)',
'alu' => 'USA (Alabama)',
'am' => 'Anguilla',
'an' => 'Andorra',
'ao' => 'Angola',
'aq' => 'Antigua and Barbuda',
'aru' => 'USA (Arkansas)',
'as' => 'American Samoa',
'at' => 'Australia',
'au' => 'Austria',
'aw' => 'Aruba',
'ay' => 'Antarctica',
'azu' => 'USA (Arizona)',
'ba' => 'Bahrain',
'bb' => 'Barbados',
'bcc' => 'Canada (British Columbia)',
'bd' => 'Burundi',
'be' => 'Belgium',
'bf' => 'Bahamas',
'bg' => 'Bangladesh',
'bh' => 'Belize',
'bi' => 'British Indian Ocean Territory',
'bl' => 'Brazil',
'bm' => 'Bermuda Islands',
'bn' => 'Bosnia and Hercegovina',
'bo' => 'Bolivia',
'bp' => 'Solomon Islands',
'br' => 'Burma',
'bs' => 'Botswana',
'bt' => 'Bhutan',
'bu' => 'Bulgaria',
'bv' => 'Bouvet Island',
'bw' => 'Belarus',
'bwr' => 'Byelorussian S.S.R.',
'bx' => 'Brunei',
'cau' => 'USA (California)',
'cb' => 'Cambodia',
'cc' => 'China',
'cd' => 'Chad',
'ce' => 'Sri Lanka',
'cf' => 'Congo (Brazzaville)',
'cg' => 'Congo (Democratic Republic)',
'ch' => 'China (Republic : 1949- )',
'ci' => 'Croatia',
'cj' => 'Cayman Islands',
'ck' => 'Colombia',
'cl' => 'Chile',
'cm' => 'Cameroon',
'cn' => 'Canada',
'cou' => 'USA (Colorado)',
'cp' => 'Canton and Enderbury Islands',
'cq' => 'Comoros',
'cr' => 'Costa Rica',
'cs' => 'Czechoslovakia',
'ctu' => 'USA (Connecticut)',
'cu' => 'Cuba',
'cv' => 'Cape Verde',
'cw' => 'Cook Islands',
'cx' => 'Central African Republic',
'cy' => 'Cyprus',
'cz' => 'Canal Zone',
'dcu' => 'USA (District of Columbia)',
'deu' => 'USA (Delaware)',
'dk' => 'Denmark',
'dm' => 'Benin',
'dq' => 'Dominica',
'dr' => 'Dominican Republic',
'ea' => 'Eritrea',
'ec' => 'Ecuador',
'eg' => 'Equatorial Guinea',
'em' => 'East Timor',
'enk' => 'England',
'er' => 'Estonia',
'err' => 'Estonia',
'es' => 'El Salvador',
'et' => 'Ethiopia',
'fa' => 'Faroe Islands',
'fg' => 'French Guiana',
'fi' => 'Finland',
'fj' => 'Fiji',
'fk' => 'Falkland Islands',
'flu' => 'USA (Florida)',
'fm' => 'Micronesia (Federated States)',
'fp' => 'French Polynesia',
'fr' => 'France',
'fs' => 'Terres australes et antarctiques françaises',
'ft' => 'Djibouti',
'gau' => 'USA (Georgia)',
'gb' => 'Kiribati',
'gd' => 'Grenada',
'ge' => 'Germany (East)',
'gh' => 'Ghana',
'gi' => 'Gibraltar',
'gl' => 'Greenland',
'gm' => 'Gambia',
'gn' => 'Gilbert and Ellice Islands',
'go' => 'Gabon',
'gp' => 'Guadeloupe',
'gr' => 'Greece',
'gs' => 'Georgia (Republic)',
'gsr' => 'Georgian S.S.R.',
'gt' => 'Guatemala',
'gu' => 'Guam',
'gv' => 'Guinea',
'gw' => 'Germany',
'gy' => 'Guyana',
'gz' => 'Gaza Strip',
'hiu' => 'USA (Hawaii)',
'hk' => 'Hong Kong',
'hm' => 'Heard and McDonald Islands',
'ho' => 'Honduras',
'ht' => 'Haiti',
'hu' => 'Hungary',
'iau' => 'USA (Iowa)',
'ic' => 'Iceland',
'idu' => 'USA (Idaho)',
'ie' => 'Ireland',
'ii' => 'India',
'ilu' => 'USA (Illinois)',
'inu' => 'USA (Indiana)',
'io' => 'Indonesia',
'iq' => 'Iraq',
'ir' => 'Iran',
'is' => 'Israel',
'it' => 'Italy',
'iu' => 'Israel-Syria Demilitarized Zones',
'iv' => 'Côte d\'Ivoire',
'iw' => 'Israel-Jordan Demilitarized Zones',
'iy' => 'Iraq-Saudi Arabia Neutral Zone',
'ja' => 'Japan',
'ji' => 'Johnston Atoll',
'jm' => 'Jamaica',
'jn' => 'Jan Mayen',
'jo' => 'Jordan',
'ke' => 'Kenya',
'kg' => 'Kyrgyzstan',
'kgr' => 'Kirghiz S.S.R.',
'kn' => 'Korea (North)',
'ko' => 'Korea (South)',
'ksu' => 'USA (Kansas)',
'ku' => 'Kuwait',
'kv' => 'Kosovo',
'kyu' => 'USA (Kentucky)',
'kz' => 'Kazakhstan',
'kzr' => 'Kazakh S.S.R.',
'lau' => 'USA (Louisiana)',
'lb' => 'Liberia',
'le' => 'Lebanon',
'lh' => 'Liechtenstein',
'li' => 'Lithuania',
'lir' => 'Lithuania',
'ln' => 'Central and Southern Line Islands',
'lo' => 'Lesotho',
'ls' => 'Laos',
'lu' => 'Luxembourg',
'lv' => 'Latvia',
'lvr' => 'Latvia',
'ly' => 'Libya',
'mau' => 'USA (Massachusetts)',
'mbc' => 'Canada (Manitoba)',
'mc' => 'Monaco',
'mdu' => 'USA (Maryland)',
'meu' => 'USA (Maine)',
'mf' => 'Mauritius',
'mg' => 'Madagascar',
'mh' => 'Macao',
'miu' => 'USA (Michigan)',
'mj' => 'Montserrat',
'mk' => 'Oman',
'ml' => 'Mali',
'mm' => 'Malta',
'mnu' => 'USA (Minnesota)',
'mo' => 'Montenegro',
'mou' => 'USA (Missouri)',
'mp' => 'Mongolia',
'mq' => 'Martinique',
'mr' => 'Morocco',
'msu' => 'USA (Mississippi)',
'mtu' => 'USA (Montana)',
'mu' => 'Mauritania',
'mv' => 'Moldova',
'mvr' => 'Moldavian S.S.R.',
'mw' => 'Malawi',
'mx' => 'Mexico',
'my' => 'Malaysia',
'mz' => 'Mozambique',
'na' => 'Netherlands Antilles',
'nbu' => 'USA (Nebraska)',
'ncu' => 'USA (North Carolina)',
'ndu' => 'USA (North Dakota)',
'ne' => 'Netherlands',
'nfc' => 'Canada (Newfoundland and Labrador)',
'ng' => 'Niger',
'nhu' => 'USA (New Hampshire)',
'nik' => 'Northern Ireland',
'nju' => 'USA (New Jersey)',
'nkc' => 'Canada (New Brunswick)',
'nl' => 'New Caledonia',
'nm' => 'Northern Mariana Islands',
'nmu' => 'USA (New Mexico)',
'nn' => 'Vanuatu',
'no' => 'Norway',
'np' => 'Nepal',
'nq' => 'Nicaragua',
'nr' => 'Nigeria',
'nsc' => 'Canada (Nova Scotia)',
'ntc' => 'Canada (Northwest Territories)',
'nu' => 'Nauru',
'nuc' => 'Canada (Nunavut)',
'nvu' => 'USA (Nevada)',
'nw' => 'Northern Mariana Islands',
'nx' => 'Norfolk Island',
'nyu' => 'USA (New York (State))',
'nz' => 'New Zealand',
'ohu' => 'USA (Ohio)',
'oku' => 'USA (Oklahoma)',
'onc' => 'Canada (Ontario)',
'oru' => 'USA (Oregon)',
'ot' => 'Mayotte',
'pau' => 'USA (Pennsylvania)',
'pc' => 'Pitcairn Island',
'pe' => 'Peru',
'pf' => 'Paracel Islands',
'pg' => 'Guinea-Bissau',
'ph' => 'Philippines',
'pic' => 'Canada (Prince Edward Island)',
'pk' => 'Pakistan',
'pl' => 'Poland',
'pn' => 'Panama',
'po' => 'Portugal',
'pp' => 'Papua New Guinea',
'pr' => 'Puerto Rico',
'pt' => 'Portuguese Timor',
'pw' => 'Palau',
'py' => 'Paraguay',
'qa' => 'Qatar',
'qea' => 'Queensland',
'quc' => 'Canada (Québec (Province))',
'rb' => 'Serbia',
're' => 'Réunion',
'rh' => 'Zimbabwe',
'riu' => 'USA (Rhode Island)',
'rm' => 'Romania',
'ru' => 'Russia (Federation)',
'rur' => 'Russian S.F.S.R.',
'rw' => 'Rwanda',
'ry' => 'Ryukyu Islands, Southern',
'sa' => 'South Africa',
'sb' => 'Svalbard',
'scu' => 'USA (South Carolina)',
'sd' => 'South Sudan',
'sdu' => 'USA (South Dakota)',
'se' => 'Seychelles',
'sf' => 'Sao Tome and Principe',
'sg' => 'Senegal',
'sh' => 'Spanish North Africa',
'si' => 'Singapore',
'sj' => 'Sudan',
'sk' => 'Sikkim',
'sl' => 'Sierra Leone',
'sm' => 'San Marino',
'snc' => 'Canada (Saskatchewan)',
'so' => 'Somalia',
'sp' => 'Spain',
'sq' => 'Swaziland',
'sr' => 'Surinam',
'ss' => 'Western Sahara',
'stk' => 'Scotland',
'su' => 'Saudi Arabia',
'sv' => 'Swan Islands',
'sw' => 'Sweden',
'sx' => 'Namibia',
'sy' => 'Syria',
'sz' => 'Switzerland',
'ta' => 'Tajikistan',
'tar' => 'Tajik S.S.R.',
'tc' => 'Turks and Caicos Islands',
'tg' => 'Togo',
'th' => 'Thailand',
'ti' => 'Tunisia',
'tk' => 'Turkmenistan',
'tkr' => 'Turkmen S.S.R.',
'tl' => 'Tokelau',
'tma' => 'Tasmania',
'tnu' => 'USA (Tennessee)',
'to' => 'Tonga',
'tr' => 'Trinidad and Tobago',
'ts' => 'United Arab Emirates',
'tt' => 'Trust Territory of the Pacific Islands',
'tu' => 'Turkey',
'tv' => 'Tuvalu',
'txu' => 'USA (Texas)',
'tz' => 'Tanzania',
'ua' => 'Egypt',
'uc' => 'United States Misc. Caribbean Islands',
'ug' => 'Uganda',
'ui' => 'United Kingdom Misc. Islands',
'uik' => 'United Kingdom Misc. Islands',
'uk' => 'United Kingdom',
'un' => 'Ukraine',
'unr' => 'Ukraine',
'up' => 'United States Misc. Pacific Islands',
'ur' => 'Soviet Union',
'us' => 'United States',
'utu' => 'USA (Utah)',
'uv' => 'Burkina Faso',
'uy' => 'Uruguay',
'uz' => 'Uzbekistan',
'uzr' => 'Uzbek S.S.R.',
'vau' => 'USA (Virginia)',
'vb' => 'British Virgin Islands',
'vc' => 'Vatican City',
've' => 'Venezuela',
'vi' => 'Virgin Islands of the United States',
'vm' => 'Vietnam',
'vn' => 'Vietnam, North',
'vp' => 'Various places',
'vra' => 'Victoria',
'vs' => 'Vietnam, South',
'vtu' => 'USA (Vermont)',
'wau' => 'USA (Washington (State))',
'wb' => 'West Berlin',
'wea' => 'Western Australia',
'wf' => 'Wallis and Futuna',
'wiu' => 'USA (Wisconsin)',
'wj' => 'West Bank of the Jordan River',
'wk' => 'Wake Island',
'wlk' => 'Wales',
'ws' => 'Samoa',
'wvu' => 'USA (West Virginia)',
'wyu' => 'USA (Wyoming)',
'xa' => 'Christmas Island (Indian Ocean)',
'xb' => 'Cocos (Keeling) Islands',
'xc' => 'Maldives',
'xd' => 'Saint Kitts-Nevis',
'xe' => 'Marshall Islands',
'xf' => 'Midway Islands',
'xga' => 'Coral Sea Islands Territory',
'xh' => 'Niue',
'xi' => 'Saint Kitts-Nevis-Anguilla',
'xj' => 'Saint Helena',
'xk' => 'Saint Lucia',
'xl' => 'Saint Pierre and Miquelon',
'xm' => 'Saint Vincent and the Grenadines',
'xn' => 'Macedonia',
'xna' => 'New South Wales',
'xo' => 'Slovakia',
'xoa' => 'Northern Territory',
'xp' => 'Spratly Island',
'xr' => 'Czech Republic',
'xra' => 'South Australia',
'xs' => 'South Georgia and the South Sandwich Islands',
'xv' => 'Slovenia',
'xx' => 'No place, unknown, or undetermined',
'xxc' => 'Canada',
'xxk' => 'United Kingdom',
'xxr' => 'Soviet Union',
'xxu' => 'USA',
'ye' => 'Yemen',
'ykc' => 'Canada (Yukon Territory)',
'ys' => 'Yemen (People\'s Democratic Republic)',
'yu' => 'Serbia and Montenegro',
'za' => 'Zambia',
);

  my ($code,$country);
  if ( ! $record ) { $crms->SetError("no record in IsForeignPub($id)"); return 'Unknown'; }
  eval {
    my $xpath = "//*[local-name()='controlfield' and \@tag='008']";
    $code  = substr($record->findvalue( $xpath ), 15, 3);
    #print "Code 1: '$code'\n";
    $code =~ s/[^a-z]//gi;
    #print "Code 2: '$code'\n";
  };
  
  $crms->SetError("failed in IsForeignPub($id): $@") if $@;
  $country = $countries{$code};
  #print "Country 1: '$country'\n";
  $country = 'Unknown' unless $country;
  #print "Country 2: '$country'\n";
  return $country;
}
