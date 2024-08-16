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
CRMS is a web app and a suite of tools for performing copyright review projects.
The primary purpose of the user interface portion is to allow trained reviewers to
navigate, research, and enter data relevant to the ultimate disposition of HathiTrust
materials whose copyright status can be investigated. CRMS also provides a convenient
place to record licensing agreements (e.g., Creative Commons) with rights holders.

Copyright and licensing determinations ultimately get exported as text files for
insertion into the Rights Database by parts of the HathiTrust infrastructure external
to CRMS. CRMS does not have write access to the Rights Database.

The "suite of tools" refers to scripts that typically run as cron jobs to manage workflows.
A copyright review proceeds via several stages (typically more than one person submits
data independently on a volume) so there is a "nightly processing" stage which moves
things along.

There are also scripts which only run (manually or otherwise) yearly, at around the time
of the January 1 "public domain day" rollover at which time a swathe of works falls into
the public domain or some other rights category.

## Built With
- Perl
- MariaDB
- [Template Toolkit](https://template-toolkit.org/)

## Prerequisites
* Docker
* Git ssh access to the repository

## Installation
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
- `bib_rights` two miscellaneous scrips related to bibliographic rights. 
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
- CRMS has its own database, called `crms`, to which it has write access.
- CRMS also uses the `ht` database/view to which it only has read access.
  - In some cases it connects to the `ht_repository` database -- this is a legacy
    usage and we should standardize on using only `ht` wherever possible.
- CRMS does not follow an MVC architecture. Most functionality is exposed via a
  top-level `CRMS` object (`cgi/CRMS.pm`). 
  - Lacking an object-oriented data model, most operations are or can be accomplished
    with the MySQL wrappers exposed by the `CRMS` object: `SelectAll` (aref),
    `SimpleSqlGet` (single value), and `PrepareSubmitSql` (for `INSERT`s).
  - Routines that retrieve database data tend to return data structures rather than
    objects. For example, `$crms->Menus()`
- `cgi/crms` is the main entry point for the CRMS web app.
  - There are a few other, more API-like, scripts in the same directory. They can
    be identified by a lack of file extension. Most return JSON.


## Usage
Create a CRMS object.
```perl
# SDRROOT is the critical proprioceptive environment variable
use lib $ENV{'SDRROOT'} . '/crms/cgi';
use CRMS;
my $crms = CRMS->new;
```

Basic database operation: list all the HTIDs and their priority in project 1 (Core) queue
```perl
my $sql = "SELECT id,priority FROM queue WHERE project=?";
my $aref = $crms->SelectAll($sql, 1);
say "$_->[0], $_->[1]" for @$aref;
```

Get the current rights for a volume.
```perl
say $crms->CurrentRightsString("mdp.35112101180794");
# "pd/add"
```

## Tests
- Tests are run by the previously-mentioned `docker compose run --rm test` command.
- By default the `test` service produces a `Devel::Cover` HTML report using
`scripts/test.sh`. The other script, `scripts/test_and_cover.sh`, is for upload to
Coveralls and is used in the GitHub action.

## Hosting
- This is not hosted in the kubernetes cluster.
- Hosted in the Hathitrust web servers like the other Babel Applications. 

## Resources
- Two of the cron jobs (`bin/pdd_collection*`) talk to a Collection Builder script which is part of
  the [monolithic babel app](https://github.com/hathitrust/babel/blob/7865e2516727ee7c6351c1bfe192ce29b7b442f7/mb/scripts/batch-collection.pl).
- Bibliographic queries are run against the HathiTrust Bib API in `cgi/Metadata.pm`.
- This also relies on [Post Zephir Processing](https://github.com/hathitrust/post_zephir_processing/)
- [Copyright Review Program at HathiTrust](https://www.hathitrust.org/copyright-review "HathiTrust CRMS home")
- [Internal University of Michigan Confluence Page](https://tools.lib.umich.edu/confluence/display/HAT/CRMS+System "Internal University of Michigan Confluence Page")
