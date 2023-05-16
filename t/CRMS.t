#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use CGI;
use Data::Dumper;
use Test::More;

use lib $ENV{SDRROOT} . '/crms/cgi';
use CRMS;




subtest '.new' => sub {
  my $crms = CRMS->new;
  isa_ok($crms, 'CRMS');
  
  subtest 'with CGI' => sub {
    my $cgi = CGI->new;
    $ENV{GATEWAY_INTERFACE} = 1;
    $crms = CRMS->new(cgi => $cgi);
    ok($crms->{cgi});
    delete $ENV{GATEWAY_INTERFACE};
  };
};

subtest '#config' => sub {
  my $crms = CRMS->new;
  isa_ok($crms->config, 'CRMS::Config');
};

subtest '#instance_name' => sub {
  subtest 'production' => sub {
    my $crms = CRMS->new(instance => 'production');
    is('production', $crms->instance_name);

    subtest 'from ENV' => sub {
      my $save_env = $ENV{'CRMS_INSTANCE'};
      $ENV{'CRMS_INSTANCE'} = 'production';
      is('production', CRMS->new->instance_name);
      $ENV{'CRMS_INSTANCE'} = $save_env;
    };
  };

  subtest 'training' => sub {
    my $crms = CRMS->new(instance => 'crms-training');
    is('training', $crms->instance_name);

    subtest 'from ENV' => sub {
      my $save_env = $ENV{'CRMS_INSTANCE'};
      $ENV{'CRMS_INSTANCE'} = 'crms-training';
      is('training', CRMS->new->instance_name);
      $ENV{'CRMS_INSTANCE'} = $save_env;
    };
  };

  subtest 'development' => sub {
    my $crms = CRMS->new(instance => '');
    is('development', $crms->instance_name);
    $crms = CRMS->new;
    is('development', $crms->instance_name);

    subtest 'from ENV' => sub {
      my $save_env = $ENV{'CRMS_INSTANCE'};
      delete $ENV{'CRMS_INSTANCE'};
      is('development', CRMS->new->instance_name);
      $ENV{'CRMS_INSTANCE'} = $save_env;
    };
  };
};

subtest '#db' => sub {
  my $crms = CRMS->new;
  isa_ok($crms->db, 'CRMS::DB');

  subtest 'without noop' => sub {
    ok(!CRMS->new->db->{noop});
  };

  subtest 'with noop' => sub {
    ok(CRMS->new(noop => 1)->db->{noop});
  };
};

subtest '#htdb' => sub {
  my $crms = CRMS->new;
  isa_ok($crms->htdb, 'CRMS::DB');
};

subtest '#WriteRightsFile' => sub {
  my $crms = CRMS->new;
  my $rights_data = join "\t", ('mdp.001', '1', '1', 'crms', 'null', '鬼塚英吉');
  $crms->WriteRightsFile($rights_data);
  my $path = $crms->get('export_path');
  ok(-f $path, "WriteRightsFile export path exists");
  open my $fh, '<:encoding(UTF-8)', $path;
  read $fh, my $buffer, -s $path;
  my @fields = split "\t", $buffer;
  is($fields[5], '鬼塚英吉', "WriteRightsFile Unicode characters survive round trip");
  close $fh;
};

subtest '#CanExportVolume' => sub {
  my $crms = CRMS->new;
  subtest 'CRMS::CanExportVolume und/nfi' => sub {
    is(0, $crms->CanExportVolume('mdp.001', 'und', 'nfi', 1));
  };

  subtest 'CRMS::CanExportVolume und/crms' => sub {
    is(0, $crms->CanExportVolume('mdp.001', 'und', 'crms', 1));
  };
};

done_testing();
