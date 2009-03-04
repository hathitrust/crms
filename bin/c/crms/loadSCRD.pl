#!/l/local/bin/perl

my $DLXSROOT;
my $DLPS_DEV;
BEGIN 
{ 
    $DLXSROOT = $ENV{'DLXSROOT'}; 
    $DLPS_DEV = $ENV{'DLPS_DEV'}; 
    require "crms.cfg";
}

use strict;
use DBI;

my %r;
my %id;
my $dbh = ConnectToDb();

processFile( $ARGV[0] );

foreach my $id ( keys %id )
{
    if ( $id{$id} > 1 ) { print "$id $id{$id} \n"; }
}

## foreach my $num ( 1..17 )
## {
##     my $f = "$DLXSROOT/prep/c/crms/slices/$num.xml";
##     print $f . "\n";
##     processFile( $f );
## }

sub processFile
{
    my $file   = shift;
    open (my $fh, $file) || die "failed to open $file: $@ \n";

    foreach my $line ( <$fh> )
    {
        chomp $line;
        if ( $line =~ /^---/ )
        {
            $id{$r{ID}}++;
            addRecord();
            %r = ();
            next;
        }

        my ($tag,$val) = split(/\:/, $line, 2);
        $tag =~ s/ //g;
        $val =~ s/^ //g;
        $val =~ s/"//g;

        if ($tag eq "ID")   { $r{'ID'}   = $val; }
        if ($tag eq "DREG") { $r{'DREG'} = $val; }
    }

    close $fh;
}

sub addRecord
{
    my $sql = qq| REPLACE INTO stanford_small (ID, DREG) VALUES ("$r{ID}", "$r{DREG}") |;

    my $sth = $dbh->prepare( $sql );
    eval { $sth->execute(); };
    if ($@) { die "failed Renewal: " . $sth->errstr; }
}

## ----------------------------------------------------------------------------
##  Function:   connect to the mysql DB
##  Parameters: nothing
##  Return:     ref to DBI
## ----------------------------------------------------------------------------
sub ConnectToDb                         ## NOTHING || ref to DB
{
    my $db_user   = $CRMSGlobals::mysqlUser;
    my $db_passwd = $CRMSGlobals::mysqlPasswd;
    my $db_server = $CRMSGlobals::mysqlServerDev;

    ## if ( ! $self->get( 'dev' ) ) { $db_server = $CRMSGlobals::mysqlServer; }

    ## print "DBI:mysql:crms:$db_server, $db_user, [passwd]\n";

    my $d = DBI->connect( "DBI:mysql:crms:$db_server", $db_user, $db_passwd,
            { RaiseError => 1, AutoCommit => 1 } ) || die "Cannot connect: $DBI::errstr";

    $d->{mysql_auto_reconnect} = 1;

    return $d;
}


