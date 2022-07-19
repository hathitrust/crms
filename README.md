# CRMS: Copyright Review Management System

![Run CI](https://github.com/hathitrust/crms/workflows/Run%20CI/badge.svg)

A web app and suite of tools for performing copyright review projects.

[Copyright Review Program at HathiTrust](https://www.hathitrust.org/copyright-review "HathiTrust CRMS home")

[Internal University of Michigan Confluence Page](https://tools.lib.umich.edu/confluence/display/HAT/CRMS+System "Internal University of Michigan Confluence Page")

```
git submodule init
git submodule update
docker-compose build
docker-compose up -d mariadb
docker-compose run --rm test
```

## Running `bib_api.pm` Coverage

```
bib_rights/cover.sh
```

Currently, with strategic `# uncoverable ...` comments made to `post_zephir_processing/bib_rights.pm`
I get the following results:

```
----------------------------------- ------ ------ ------ ------ ------ ------
File                                  stmt   bran   cond    sub   time  total
----------------------------------- ------ ------ ------ ------ ------ ------
...
..._zephir_processing/bib_rights.pm  100.0  100.0   85.7  100.0    6.1   98.6
```

I have had little luck with `Devel::Cover` condition coverage, so all we're really
interested in is statement and branch coverage.

The JSON test data, MARC XML, and fake OCLC fed gov exceptions in `t/fixtures` are
to be considered "fixed" (the JSON test data in particular) as they were generated
against the baseline bib rights algorithm. To regenerate these files (to add test volumes, for example),
run

```
docker-compose run --rm test perl /htapps/babel/crms/bib_rights/gen_bib_rights_tests.pl
```

Note `gen_bib_rights_tests.pl` will not remove fixtures that have been removed from its
internal list. But it is safe to delete the `fixtures/bib_rights` directory and regenerate it.
