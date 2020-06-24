#!/usr/bin/perl -w

use strict;
use Test::Harness;

my @test_files = ('/crms/t/Project.t',
                  '/crms/t/CRMS.t');
runtests map {$ENV{'SDRROOT'}. $_} @test_files;
