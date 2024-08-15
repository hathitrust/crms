<br/>
  <p align="center">
  CRMS: Copyright Review Management System
  
![Run Tests](https://github.com/hathitrust/crms/workflows/Run%20Tests/badge.svg)  [![Coverage Status](https://coveralls.io/repos/github/hathitrust/crms/badge.svg?branch=main)](https://coveralls.io/github/hathitrust/crms?branch=main)
  
  A web app and suite of tools for performing copyright review projects.
  </p>
  <br/>
  <br/>



## Table Of Contents

* [About the Project](#about-the-project)
* [Built With](#built-with)
* [Prerequisites](#prerequisites)
* [Installation](#installation)
* [Project Structure](#project-structure)
* [Functionality](#functionality)
* [Usage](#usage)
* [Tests](#tests)
* [Hosting](#hosting)
* [Resources](#resources)

## About The Project
- Expand on "A web app and suite of tools for performing copyright review projects." and it's importance, outside reach into collection builder, etc... Keep it at a high level.

## Built With
- Perl
- MariaDB
- [Template Toolkit](https://template-toolkit.org/)

## Prerequisites
* Docker
* Git ssh access to the repository

## Installation
- This section clearly outline the steps taken to get the project installed on the system. This is a great place to include commands that have been run and configuration files that have been changed.

1. Clone the repo & cd into `crms/`
```sh
git clone git@github.com:hathitrust/crms.git
cd crms/
```

2. Pull the Post Zepher Processing Repo as a sub-module

```sh
git submodule init
git submodule update
```

3. Stand up the docker environment and run the tests.
   - This will run two database services and make sure that the local MariaDB connections are healthy.
```
docker compose build
docker compose run --rm test
```


### Project Structure
- `bib_rights` miscellaneous scrips used for bibliographic rights. 
- `bin` For the most part these are actions and reports run as cron jobs
- `cgi` Main entry point `cgi/crms` as well as Perl modules and view templates
  - This is the directory most in need of reorganization. In future much of its
content will be migrated to `lib` and `views`.
- `docker` Database seeds
- `lib` Perl modules (new development and refactored modules from `cgi`)
- `prep` Destination for some log files and reports
- `scripts` Testing wrappers run as part of development or by GitHub
- `t` Tests
- `web` Static assets including images, JS, CSS

## Functionality
- Most functionality is exposed via the top-level `CRMS` object, including
the all-important `SelectAll` (aref), `SimpleSqlGet` (single value), and
`PrepareSubmitSql` wrappers around `DBI` functions.


## Usage
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

## Tests
- These tests are run when the docker command `docker compose run --rm test` is executed from above.
- By default the `test` service produces a `Devel::Cover` HTML report using
`scripts/test.sh`. The other script, `scripts/test_and_cover.sh`, is for upload to
Coveralls and is used in the GitHub action.

## Hosting
- This is not hosted in the kubernetes cluster.
- Hosted in the Hathitrust web servers like the other Babel Applications. 

## Resources
- At a low level, this talks to a "collection builder" script located in the [monolithic babel app](https://github.com/hathitrust/babel/blob/7865e2516727ee7c6351c1bfe192ce29b7b442f7/mb/scripts/batch-collection.pl).
- This also relies on [Post Zepher Processing](https://github.com/hathitrust/post_zephir_processing/)
- [Copyright Review Program at HathiTrust](https://www.hathitrust.org/copyright-review "HathiTrust CRMS home")
- [Internal University of Michigan Confluence Page](https://tools.lib.umich.edu/confluence/display/HAT/CRMS+System "Internal University of Michigan Confluence Page")
