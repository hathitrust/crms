# CRMS Binaries

Most programs in this directory run as cron jobs. They are listed here with
brief descriptions. For more complete documentation, consult the `USAGE` strings
or invoke with the `-h` flag.

## Executable Files

`bib_newyear.pl`
Reports proposed new rights for volumes that would otherwise not be eligible
for bib rights determination.

`bib_rights.pl`
Reports the bibliographic rights for one or more HathiTrust and/or catalog ids.

`candidatespurge.pl`
Reports on volumes that are no longer eligible for candidacy
in the rights database and removes them from the system.

`cc.pl`
Reports on volumes suspected to be eligible for Creative Commons license.

`criticize.pl`
Runs `Perl::Critic` on all `.pm`, `.pl`, and extensionless files
in `cgi/` and `bin/`.
This is offered as a sort of sanity check and is not currently part of the
test suite.

`duplicates.pl`
Reports on determinations for volumes that have duplicates,
multiple volumes, or conflicting determinations.

`htreport.pl`
Sends biweekly activity reports to HathiTrust administrators.

`inherit.pl`
Reports on the volumes that can inherit from this morning's export, or in the
case of candidates inheritance, recently-ingested volumes that can inherit
an earlier CRMS determination.

`institutions.pl`
Produces TSV file of HT institution name and identifier for download at
<https://www.hathitrust.org/institution_identifiers>

`licensing_export.pl`
Exports .rights file based on unexported crms.licensing table entries.
This is expected to run every 15 minutes or so.

`licensing_report.pl`
Daily summary of licensing exports.

`mailer.pl`
Sends accumulated help requests and announcements to and from
<crms-experts@umich.edu>.

`miscstats.pl`
Reports on user progress, patron requests, and past month's invalidations
and swiss reviews.

`newyear.pl`
Reports on and submits new determinations for previous determinations
that may now, as of the new year, have had copyright expire from `ic*`
to either `pd*` or `icus`.

`overnight.pl`
Processes reviews, exports determinations, updates candidates,
updates the queue, recalculates user stats, and clears stale locks.
This is the "heartbeat" of CRMS.

`reminder.pl`
Send reminder e-mail to active reviewers who have not submitted reviews in
the past two weeks.

`renewals.pl`
Produces TSV file of HTID and renewal ID for Zephir download at
<https://www.hathitrust.org/files/CRMSRenewals.tsv>

`reviewdata.pl`
One-off script for migrating CRMS-US renNum/renDate information
to reviewdata table. (Will probably be archived in `legacy/`)

`title_reports.pl`
Creates LaTeX title reports for each State Gov Docs reviewer.

`training.pl`
Populates the training database with examples (validated single reviews)
from production so that the queue size is increased to a target size.

`warm_cache.pl`
Call `imgsrv` script to cache frontmatter page images for volumes in the queue.

`weekly.pl`
Sends weekly activity report.

## Other Files

`rdist.app`
`rdist` configuration for deploying from test.babel to production.

