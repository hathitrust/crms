# CRMS: Copyright Review Management System

![Run CI](https://github.com/hathitrust/crms/workflows/Run%20CI/badge.svg) [![Coverage Status](https://coveralls.io/repos/github/hathitrust/crms/badge.svg?branch=main)](https://coveralls.io/github/hathitrust/crms?branch=main)

A web app and suite of tools for performing copyright review projects.

[Copyright Review Program at HathiTrust](https://www.hathitrust.org/copyright-review "HathiTrust CRMS home")

[Internal University of Michigan Confluence Page](https://tools.lib.umich.edu/confluence/display/HAT/CRMS+System "Internal University of Michigan Confluence Page")

```
git submodule init
git submodule update
docker compose build
docker compose up -d mariadb
docker compose run --rm test
```

## Running Tests with Coverage

```
scripts/cover.sh
```

The other coverage script -- `scripts/test_and_cover.sh` -- is used by GitHub actions
to upload results to Coveralls.

## What is Where

- `bin` For the most part these are actions and reports run as cron jobs
- `cgi` Main entry point `cgi/crms` as well as Perl modules and view templates
- `docker` Database seeds
- `lib` Perl modules (new development and refactored modules from `cgi`)
- `prep` Destination for some log files and reports
- `scripts` Binaries run as part of development or by GitHub
- `t` Tests
- `web` Static assets including images, JS, CSS

`cgi` is the directory most in need of reorganization. In future much of its
content will be migrated to `lib` and `views`.

## Hello World

Most functionality is exposed via the top-level `CRMS` object, including
the all-important `SelectAll` (aref), `SimpleSqlGet` (single value), and
`PrepareSubmitSql` wrappers around `DBI` functions.

```perl
# SDRROOT is the critical proprioceptive environment variable
use lib $ENV{'SDRROOT'} . '/crms/cgi';
use CRMS;
my $crms = CRMS->new;
# List all the HTIDs and their priority in project 1 (Core)
my $sql = "SELECT id,priority FROM queue WHERE project=?";
my $aref = $crms->SelectAll($sql, 1);
print "$_->[0], $_->[1]\n" for @$aref;
```
