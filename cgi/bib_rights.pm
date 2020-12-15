package bib_rights;

=head1 SYNOPSIS

    use bib_rights;
    my $br = bib_rights->new();

    my $bib;		# MARC::Record structure
    my $bib_key;	# system number for $bib
    my $hathi_id;	# full hathi object id
    my $description;	# item-level enum/chron

    my $bib_info = $br->get_bib_info($bib, $bib_key);
    my $bri = $br->get_bib_rights_info($hathi_id, $bib_info, $description);
    
Rights info structure:
  my $bri = {
    'bib_key' => $bib_key,
    'id' => $barcode_ns,
    'attr' => 'und',
    'reason' => 'default',
    'date_used' => '',
    'date_type' => '',
    'date1' => '',
    'date2' => '',
    'vol_date' => $vol_date,
    'desc' => $item_description,
    'date_munged' => 0,
  };
  
=cut

use strict;
no strict 'refs';
no strict 'subs';
use Exporter;
use Sys::Hostname;
use DBI;
use Data::Dumper;
use YAML qw'LoadFile';
use MARC::Record;
use DB_File;
use File::Basename;

our @ISA = qw( Exporter );
our @EXPORT = qw ( get_bib_info get_bib_rights_info debug_line get_volume_date );

sub new {
  my $class = shift;
  $class = ref($class) || $class; # Handle cloning

  my $self;
  my $today = getDate();
  $ENV{'BIB_RIGHTS_DATE'} and do { # override date for bib rights determination
    print STDERR "current date $today overridden from env: BIB_RIGHTS_DATE=$ENV{'BIB_RIGHTS_DATE'}\n";
    $today = $ENV{'BIB_RIGHTS_DATE'};
  };
  my $year = substr($today,0,4);
  $self->{max_vol_date} = $year + 5;

  # get year for checking NTIS rolling copyright cutoff
  $self->{ntis_cutoff_year} = $year - 6;

  # get values for pd cutoff dates
  $self->{us_pd_cutoff_year} = $year - 95;
  $self->{non_us_pd_cutoff_year} = $year - 140;
  $self->{can_aus_pd_cutoff_year} = $year - 120;

  foreach my $cutoff ("us_pd_cutoff_year", "non_us_pd_cutoff_year", "can_aus_pd_cutoff_year", "ntis_cutoff_year") {
    print STDERR "$cutoff: $self->{$cutoff}\n";
  }

  #  db file of us cities--used for checking imprint field with multiple subfield
  my $us_cities_db = dirname(__FILE__) . "/data/us_cities.db";
  my %US_CITIES;
  tie %US_CITIES, "DB_File", $us_cities_db, O_RDONLY, 0644, $DB_BTREE or die "can't open db file $us_cities_db: $!";
  $self->{US_CITIES} = \%US_CITIES;

  my $us_fed_pub_exceptions = {};
  $ENV{'us_fed_pub_exception_file'} and do { # us fed pub exception file (file of oclc number of records that shouldn't be considered us fed docs, regardless of 008 coding)
    my $us_fed_pub_exception_file = $ENV{'us_fed_pub_exception_file'};
    if (-e $us_fed_pub_exception_file) {
      open (US_FED_PUB_EXCEPTIONS, "<$us_fed_pub_exception_file") or die "can't open $us_fed_pub_exception_file for input: $!\n";
      print STDERR "using $us_fed_pub_exception_file for us fed pub exceptions\n";
      my $exception_count = 0;
      while (<US_FED_PUB_EXCEPTIONS>) {
        chomp();
        $us_fed_pub_exceptions->{$_}++;
        $exception_count++;
      }
      print STDERR "$exception_count oclc numbers in us fed pub exception list\n";
    } else {
      print STDERR "us_fed_pub_exception_file set to $us_fed_pub_exception_file, not readable\n";
    }
  };
  $self->{us_fed_pub_exceptions} = $us_fed_pub_exceptions;

  # globals
  return bless $self, $class;
}

sub get_bib_rights_info {
  my $self = shift;
  my $barcode_ns = shift;	# full object id
  my $bib_info = shift;		# hash of bib info from get_bib_info
  my $item_description = shift;	# item-level enum_chron

  my $vol_date = $self->get_volume_date($item_description);

  # initialize rights info structure
  my $ri = {
    'bib_key' => $bib_info->{"bib_key"},
    'bib_fmt' => $bib_info->{"bib_fmt"},
    'id' => $barcode_ns,
    'attr' => 'und',
    'reason' => 'default',
    'date_used' => '',
    'date_desc' => '',
    'date_type' => $bib_info->{"date_type"},
    'date1' => $bib_info->{"date1"},
    'date2' => $bib_info->{"date2"},
    'orig_date1' => $bib_info->{"orig_date1"},
    'orig_date2' => $bib_info->{"orig_date2"},
    'vol_date' => $vol_date,
    'desc' => $item_description,
    'date_munged' => 0,
    'gov_pub' => $bib_info->{"gov_pub"},
    'pub_place' => $bib_info->{"pub_place"},
    'pub_country' => substr($bib_info->{"pub_place"},2,1),
    'us_fed_doc' => $bib_info->{"us_fed_doc"},
  };
  
  $self->set_date($ri) or do {
    $ri->{'reason'} = $ri->{'date_desc'};
    return $ri;
  };

  SET_RIGHTS: {
    $ri->{'gov_pub'} eq 'f' and $ri->{'pub_country'} eq 'u' and do {
    #$ri->{'us_fed_doc'} and do {
      $ri->{'attr'} = "pd";
      $ri->{'reason'} = "US fed doc";
      $bib_info->{"us_fed_pub_exception"} or last SET_RIGHTS;	# no exceptions, exit
      # us gov pub exceptions--check pub date
      # set date cutoff for exceptions
      my $date_cutoff = $self->{us_pd_cutoff_year}; 	#default
      $bib_info->{"us_fed_pub_exception"} eq "NTIS" and $date_cutoff = $self->{ntis_cutoff_year}; # rolling cutoff for NTIS
      if ($ri->{'date_used'} >= $date_cutoff) {
        $ri->{'attr'} = "ic";
        $ri->{'date_munged'} = 0;			# don't care about date munging
        $ri->{'reason'} = "US fed doc--$bib_info->{'us_fed_pub_exception'}: pubdate >= " . $date_cutoff;
      } else {
        $ri->{'attr'} = "pd";
        $ri->{'date_munged'} = 0;			# don't care about date munging
        $ri->{'reason'} = "US fed doc--$bib_info->{'us_fed_pub_exception'}: pubdate < " . $date_cutoff;
      } 
      last SET_RIGHTS;
    };
    if ($ri->{'pub_country'} eq "u") {			# US publication
      $bib_info->{"mult_260a_non_us"} and $ri->{'date_used'} >= $self->{non_us_pd_cutoff_year} and $ri->{'date_used'} < $self->{us_pd_cutoff_year} and do {
        $ri->{'attr'} = "pdus";
        $ri->{'reason'} = "US $ri->{'date_desc'} between $self->{non_us_pd_cutoff_year} and $self->{us_pd_cutoff_year} and multiple 260/264 places";
        last SET_RIGHTS;
      };
      $ri->{'date_used'} < $self->{us_pd_cutoff_year} and do {
        $ri->{'attr'} = "pd";
        $ri->{'reason'} = "US $ri->{'date_desc'} < $self->{us_pd_cutoff_year}";
        last SET_RIGHTS;
      };
      $ri->{'attr'} = "ic";
      $ri->{'reason'} = "US $ri->{'date_desc'} >= $self->{us_pd_cutoff_year}";
      last SET_RIGHTS;
    } elsif ($ri->{'pub_place'} =~ /^(..c|cn |at |aca|qea|tma|vra|wea|xga|xna|xoa|xra)$/) {	# australia or canada
      $ri->{'date_used'} < $self->{can_aus_pd_cutoff_year} and do {
        $ri->{'attr'} = "pd";
        $ri->{'reason'} = "canada/australia $ri->{'date_desc'} < $self->{can_aus_pd_cutoff_year}";
        last SET_RIGHTS;
      };
      $ri->{'date_used'} >= $self->{can_aus_pd_cutoff_year} and $ri->{'date_used'} < $self->{us_pd_cutoff_year} and do {
        $ri->{'attr'} = "pdus";
        $ri->{'reason'} = "canada/australia $ri->{'date_desc'} between $self->{can_aus_pd_cutoff_year} and $self->{us_pd_cutoff_year}";
        last SET_RIGHTS;
      };
      $ri->{'attr'} = "ic";
      $ri->{'reason'} = "non-US $ri->{'date_desc'} >= $self->{us_pd_cutoff_year}";
      last SET_RIGHTS;
    } else { 					# other non-us
      $ri->{'date_used'} < $self->{non_us_pd_cutoff_year} and do {
        $ri->{'attr'} = "pd";
        $ri->{'reason'} = "non-US $ri->{'date_desc'} < $self->{non_us_pd_cutoff_year}";
        last SET_RIGHTS;
      };
      $ri->{'date_used'} >= $self->{non_us_pd_cutoff_year} and $ri->{'date_used'} < $self->{us_pd_cutoff_year} and do {
        $ri->{'attr'} = "pdus";
        $ri->{'reason'} = "non-US $ri->{'date_desc'} between $self->{non_us_pd_cutoff_year} and $self->{us_pd_cutoff_year}";
        last SET_RIGHTS;
      };
      $ri->{'attr'} = "ic";
      $ri->{'reason'} = "non-US $ri->{'date_desc'} >= $self->{us_pd_cutoff_year}";
      last SET_RIGHTS;
    }	# pub_place_17 ne "u"
    #die "SET_RIGHTS:  fatal error\n";
  } 	# SET_RIGHTS
  $ri->{'date_munged'} and $ri->{'attr'} eq "ic" and $ri->{'attr'} = "und";
  return $ri;
}

sub set_date {  
  my $self = shift;
  my $ri = shift;
  $ri->{'date_desc'} = 'default';
  
  $ri->{"bib_fmt"} eq 'SE' and $ri->{"vol_date"} > $self->{"max_vol_date"} and do {
    $ri->{"date_desc"} = "serial item date > max_vol_date";
    $ri->{"vol_date"} = '';
  };
  $ri->{"bib_fmt"} eq 'SE' and $ri->{"vol_date"} and do {
    $ri->{"date_desc"} = "serial item date";
    $ri->{"date_used"} = $ri->{"vol_date"};
    return 1;
  }; 
  $ri->{"date_type"} eq 'm' and do { # multiple dates--use date 2 
    $ri->{"date2"} and do {
      $ri->{"date_used"} = $ri->{"date2"};
      $ri->{"date_desc"} = "bib date2, date type m";
      return 1;
    };
    $ri->{"date1"} and do {
      $ri->{"date_used"} = $ri->{"date1"};
      $ri->{"date_desc"} = "bib date1, date type m";
      return 1;
    };
    $ri->{"date_desc"} = "date type m--no date";
    return 0;
  };
  $ri->{"date_type"} eq 't' and do { #  Publication date and copyright date
    $ri->{"date2"} and do {
      $ri->{"date_used"} = $ri->{"date2"};
      $ri->{"date_desc"} = "bib date2, date type t";
      return 1;
    };
    $ri->{"date1"} and do {
      $ri->{"date_used"} = $ri->{"date1"};
      $ri->{"date_desc"} = "bib date1, date type t";
      return 1;
    };
    $ri->{"date_desc"} = "date type t--no date1";
    return 0; 
  };
  $ri->{"date_type"} eq 'r' and do { # reprint/reissue, use date1 (date of reprint/reissue)
    $ri->{"date1"} and do {
      $ri->{"date_used"} = $ri->{"date1"};
      $ri->{"date_desc"} = "bib date1, date type r";
      $ri->{"date1"} ne $ri->{'orig_date1'} and $ri->{"date_munged"}++;
      return 1;
    };
    $ri->{"date_desc"} = "date type r--no date1";
    return 0;
  };
  $ri->{"date_type"} eq 'e' and do { # detailed date, use date1 (date2 has month and day)
    $ri->{"date1"} and do {
      $ri->{"date_used"} = $ri->{"date1"};
      $ri->{"date_desc"} = "bib date1, date type e";
      $ri->{"date1"} ne $ri->{'orig_date1'} and $ri->{"date_munged"}++;
      return 1;
    };
    $ri->{"date_desc"} = "date type e--no date1";
    return 0;
  };
  $ri->{"bib_fmt"} eq 'SE' and $ri->{"date_munged"}++; 	# no volume date for serial
  $ri->{"date2"} and $ri->{"date2"} > $ri->{"date1"} and do {
    $ri->{"date_used"} = $ri->{"date2"};
    $ri->{"date_desc"} = "bib date2";
    $ri->{"date2"} ne $ri->{'orig_date2'} and $ri->{"date_munged"}++;
    return 1;
  };
  $ri->{"date1"} and do {
    $ri->{"date_used"} = $ri->{"date1"};
    $ri->{"date_desc"} = "bib date1";
    $ri->{"date1"} ne $ri->{'orig_date1'} and $ri->{"date_munged"}++;
    return 1;
  };
  $ri->{"date_desc"} = "default--no date";
  # no date set--check for us fed doc
  $ri->{"us_fed_doc"} and do {			# US fed doc
    $ri->{"date_used"} = '9999';
    $ri->{"date_desc"} = 'no date--US fed doc';
    return 1;
  };
  $ri->{"date_desc"} = 'no date';
  return 0;
}

sub debug_line {
  my $self = shift;
  my $bib_info = shift;
  my $rights_info = shift;
  return join("\t",
                        $bib_info->{bib_key},
                        $rights_info->{id},
                        $rights_info->{attr},
                        $rights_info->{reason},
                        $bib_info->{bib_fmt},
                        $rights_info->{date_used},
                        $rights_info->{date_type},
                        $rights_info->{date1},
                        $bib_info->{orig_date1},
                        $rights_info->{date2},
                        $bib_info->{orig_date2},
                        $bib_info->{pub_place},
                        $rights_info->{vol_date},
                        $rights_info->{desc},
                        $bib_info->{f008},
                        $bib_info->{imprint},
                        $bib_info->{bib_status},
                        $rights_info->{date_munged},
                   );
}

sub get_bib_data {
  # return a string of data for a bib field and subfields
  my $bib = shift;
  my $tag = shift;
  my $subfields = shift;
  my $data = [];
  my $field_string;
  TAG:foreach my $field ( $bib->field($tag) )  {
    $field_string = $field->as_string($subfields) and push @$data, $field_string;
  }
  return join(",", @$data);
}

sub get_bib_info {
  my $self = shift;
  my $bib = shift;		# MARC record structure
  my $bib_key = shift;		# bib key

  my $field; 
  
  my  $bi = {};
  my $field;
  my ($f_imprint);

  $bi->{bib_fmt} = getBibFmt($bib_key, $bib);
  $bib->field('008') and $bi->{f008} = $bib->field('008')->as_string();

  ($bi->{bib_fmt} and $bi->{f008}) or do {
    print STDERR "get_bib_info: no 008 or FMT field for $bib_key\n";
    return {};
  };
  length($bi->{f008}) < 40 and do {
    $bi->{f008} = sprintf("%-40.40s", $bi->{f008});
  };

  my $oclc_numbers = get_oclc_numbers($bib, $bib_key);

  GET_IMPRINT: {
    $field = $bib->field('260') and do {
      $f_imprint = $field;
      $bi->{imprint} = output_field($field);		# text version of the field in the bi hash
      $bi->{imprint_2} = $field->as_string();		# text version of the field in the bi hash
      last GET_IMPRINT;
    };
    foreach my $field ($bib->field('264')) { 	# check for RDA imprint--264 ind2=1
      $field->indicator(2) == 1 and do {
        #print STDERR "get_bib_info: $bib_key 264 field used for imprint\n";
        $f_imprint = $field;
        $bi->{imprint} = output_field($field);		# text version of the field in the bi hash
        $bi->{imprint_2} = $field->as_string();		# text version of the field in the bi hash
        last GET_IMPRINT;
      };
    }
  }
  
  $bi->{lang} = substr($bi->{f008}, 35, 3);
  $bi->{pub_place} = clean_pub_place(substr($bi->{f008},15,3));
  $bi->{gov_pub} = substr($bi->{f008},28,1);
  $bi->{date_type} = substr($bi->{f008},6,1);
  $bi->{orig_date1} = substr($bi->{f008},7,4);
  $bi->{orig_date2} = substr($bi->{f008},11,4);
  $bi->{date1} = clean_date($bi->{orig_date1});
  $bi->{date2} = clean_date($bi->{orig_date2});

  $bi->{bib_status} = '';

  #check us records for mulitple subfield a in imprint field
  CHECK_IMPRINT: {
    $bi->{pub_place} !~ /u$/ and last CHECK_IMPRINT; #non-us, skip check
    $f_imprint or do {
      #print STDERR "get_bib_info: $bib_key: no imprint field\n";
      last CHECK_IMPRINT;
    };
    my @suba = $f_imprint->subfield('a');
    my $suba_cnt = scalar(@suba);
    $suba_cnt <= 1 and last CHECK_IMPRINT;	# exit check
    my $non_us_city = 0;
    foreach my $suba (@suba) {
      $suba =~ tr/A-Za-z / /c;
      $suba =~ s/^\s*(.*?)\s*$/$1/;
      $suba = lc($suba);
      $suba =~ s/ and / /;
      $suba =~ s/^and //;
      $suba =~ s/ and$//;
      $suba =~ s/ etc / /;
      $suba =~ s/ etc$//;
      $suba =~ s/ dc / /;
      $suba =~ s/\s+/ /g;
      $suba =~ s/^\s*(.*?)\s*$/$1/;
      $self->{US_CITIES}->{$suba} or do {
        $non_us_city++;
        #print NON_US join("\t", $bib_key, $suba, output_field($f_imprint)), "\n";
      };
    }
    if ($non_us_city) { 
      $bi->{mult_260a_non_us} = 1;
    }
  };

  CHECK_GOV: {
    $bi->{us_fed_doc} = 0;	# set default
    $bi->{gov_pub} eq "f" and substr($bi->{pub_place},2,1) eq 'u' and do { # us fed doc
      foreach my $oclc (@$oclc_numbers) {
        $self->{us_fed_pub_exceptions}->{$oclc} and do {
          $bi->{us_fed_pub_exception} = "exception list";
          print STDERR "$bib_key: $oclc on us fed pub exception list\n";
          last CHECK_GOV;
        };
      }
      foreach $field ($bib->field('400|410|411|440|490|800|810|811|830')) {
        $field->as_string() =~ /(nsrds|national standard reference data series)/i and do {
          $bi->{us_fed_pub_exception} = "NIST-NSRDS";
          last CHECK_GOV; 
        };
      }
      $bi->{imprint} =~ /ntis|national technical information service/i and do {
        $bi->{us_fed_pub_exception} = "NTIS";
        last CHECK_GOV; 
      };
      foreach my $field ($bib->field('260|264|110|710')) {
        $field->as_string() =~ /armed forces communications (association|communications and electronics association)/i and do {
          $bi->{us_fed_pub_exception} = "armed forces comm assoc";
          last CHECK_GOV; 
        };
      }
      foreach my $field ($bib->field('260|264|110|710')) {
        my $field_string = $field->as_string();
        #$field_string =~ /national research council \(u\.s\.\)/i and do {
        $field_string =~ /national research council/i and $field_string !~ /canada/i and do {
          $bi->{us_fed_pub_exception} = "national research council";
          last CHECK_GOV; 
        };
      }
      foreach my $field ($bib->field('260|264|110|130|710')) {
        $field->as_string() =~ /smithsonian/i and do {
          $bi->{us_fed_pub_exception} = "smithsonian";
          last CHECK_GOV; 
        };
      }
      foreach my $field ($bib->field('100|110|111|700|710|711')) {
        $field->as_string() =~ /federal reserve/i and do {
          $bi->{us_fed_pub_exception} = "federal reserve";
          last CHECK_GOV; 
        };
      }
      $bi->{us_fed_doc} = 1;	# no exceptions, set us_fed_doc flag
    };
  }

  $bi->{bib_key} = $bib_key;

  return $bi;
}

sub clean_pub_place {
  my $pub_place = shift;
  $pub_place = lc($pub_place);
  $pub_place =~ tr/?|^/ /;
  $pub_place =~ /^[a-z ]{2,3}/ or return '   ';
  $pub_place =~ /^pr/ and return 'pru';
  $pub_place =~ /^us/ and return 'xxu';
  #$pub_place eq '   ' and return '';
  return $pub_place;
}

sub get_volume_date {
  my $self = shift;
  my $item_desc = lc(shift);
  $item_desc or return '';
  my @vol_date = ();
  my $orig_desc = $item_desc;
  my $low;
  my $high;
  my $date;
  
  # umdl item descriptions may contain NNNN.NNN--if so, return null
  $item_desc =~ /^\d{4}\.[a-z0-9]{3}$/i and return '';

  # check for tech report number formats
  $item_desc =~ /^\d{1,3}-\d{4}$/ and return '';

  # strip confusing page/part data:
  #39015022710779: Title 7 1965 pt.1090-end
  #39015022735396: v.23 no.5-8 1984 pp.939-1830
  #39015022735701: v.77 1983 no.7-12 p.673-1328
  #39015022735750: v.75 1981 no.7-12 p.673-1324
  #no. 3086/3115 1964
  #no.3043,3046
  #39015040299169      no.5001-5007,5009-5010
  #$item_desc =~ s/(v\.|no\.|p{1,2}\.|pt\.)[\d,-]+//g;
  $item_desc =~ s/\b(v\.\s*|no\.\s*|p{1,2}\.\s*|pt\.\s*)[\d,-\/]+//g;

  # strip months
  $item_desc =~ s/(january|february|march|april|may|june|july|august|september|october|november|december)\.{0,1}-{0,1}//gi;
  $item_desc =~ s/(jan|feb|mar|apr|may|jun|jul|aug|sept|sep|oct|nov|dec)\.{0,1}-{0,1}//gi;
  $item_desc =~ s/(winter|spring|summer|fall|autumn)-{0,1}//gi;
  $item_desc =~ s/(supplement|suppl|quarter|qtr|jahr)\.{0,1}-{0,1}//gi;
  
  # report numbers 
  #no.CR-2291 1973
  $item_desc =~ s/\b[a-zA-Z.]+-\d+//;

  # check for date ranges: yyyy-yy
  #($low, $high) = ( $item_desc =~ /\b(\d{4})\-(\d{2})\b/ ) and do {
  #($low, $high) = ( $item_desc =~ /\s(\d{4})\-(\d{2})\s/ ) and do {
  #$item_desc =~ /\b(\d{4})\-(\d{2})\b/ and do {
  $item_desc =~ /\b(\d{4})[-\/](\d{2})\b/ and do {
    $low = $1;
    $high = $2;
    $high = substr($low,0,2) . $high;
    push(@vol_date, $high);
  };

  # check for date ranges: yyyy-y
  #($low, $high) = ( $item_desc =~ /\b(\d{4})\-(\d)\b/ ) and do {
  ($low, $high) = ( $item_desc =~ /\s(\d{4})\-(\d)\s/ ) and do {
    $high = substr($low,0,3) . $high;
    push(@vol_date, $high);
  };

  # look for 4-digit strings
#  $item_desc =~ tr/0-9u/ /cs;           # xlate non-digits to blank (keep "u")
  $item_desc =~ tr/u^|/9/;              # translate "u" to "9"
  push (@vol_date, $item_desc =~ /\b(\d{4})\b/g);

  # return the maximum year
  @vol_date = sort(@vol_date);
  my $vol_date =  pop(@vol_date);
  # reality check--
  $vol_date < 1500 and $vol_date = '';
  return $vol_date;
}  

sub clean_date {
  my $date = shift;
  $date eq '0000' and return '';
  $date =~ /^\d{4}$/ and return $date;  # 4 digits, just return it
  $date =~ s/\|\|\|\|//;                # 4 fill characters, translate to null
  $date =~ s/\^\^\^\^//;                # 4 fill characters, translate to null
  $date =~ s/\?\?\?\?//;                # 4 question marks, translate to null
  $date =~ s/\s{4}//;                   # 4 whitespace characters, translate to null
  $date =~ tr/u^|/9/;                   # translate "u" to "9"
  $date and $date !~ /\d{4}/ and $date = '';    # something there, but non-numeric, set to null
  return $date;
}


sub getDate {
  my $inputDate = shift;
  if (!defined($inputDate)) { $inputDate = time; }
  my ($ss,$mm,$hh,$day,$mon,$yr,$wday,$yday,$isdst) = localtime($inputDate);
  my $year = $yr + 1900;
  $mon++;
  my $fmtdate = sprintf("%4.4d%2.2d%2.2d:%2.2d:%2.2d:%2.2d",$year,$mon,$day,$hh,$mm,$ss);
  return $fmtdate;
}

sub getBibFmt {
  my $bib_key = shift;
  my $record = shift;
  my $ldr = $record->leader();
  my $recTyp = substr($ldr,6,1);
  my $bibLev = substr($ldr,7,1);
  $recTyp =~ /[at]/ and $bibLev =~ /[acdm]/ and return "BK";
  $recTyp =~ /[m]/ and $bibLev =~ /[abcdms]/ and return "CF";
  $recTyp =~ /[gkor]/ and $bibLev =~ /[abcdms]/ and return "VM";
  $recTyp =~ /[cdij]/ and $bibLev =~ /[abcdms]/ and return "MU";
  $recTyp =~ /[ef]/ and $bibLev =~ /[abcdms]/ and return "MP";
  $recTyp =~ /[a]/ and $bibLev =~ /[bsi]/ and return "SE";
  $recTyp =~ /[bp]/ and $bibLev =~ /[abcdms]/ and return "MX";
  $bibLev eq 's' and do {
    print STDERR "$bib_key: biblev s, rectype $recTyp, fmt set to SE\n";
    return "SE";
  };
  # no match  --error
  print STDERR "$bib_key: can't set format, recTyp: $recTyp, bibLev: $bibLev\n";
  return 'XX';
}

sub output_field {
  my $field = shift;
  my $out = "";
  $out .= $field->tag()." ";
  if ($field->tag() lt '010') { $out .= "   ".$field->data; }
  else {
    $out .= $field->indicator(1).$field->indicator(2)." ";
    my @subfieldlist = $field->subfields();
    foreach my $sfl (@subfieldlist) {
      $out.="|".shift(@$sfl).shift(@$sfl);
    }
  }
  return $out;
}

sub get_oclc_numbers {
  # return oclc number 
  my $bib = shift;
  my $bib_key = shift;
  my $oclc_num_hash = {};
  my $oclc_num_list = [];
  F035:foreach my $field ($bib->field('035')) {
    my $sub_a = $field->as_string('a') or next F035;
    $sub_a =~ /(oclc|ocolc|ocm|ocn)/i and do {
      my ($oclc_num) = $sub_a =~ /(\d+)/;
      $oclc_num_hash->{$oclc_num + 0}++;
      next F035;
    };
  }
  @$oclc_num_list = sort keys %$oclc_num_hash;
  return $oclc_num_list;
}


1;
