use crms;

LOCK TABLES `authorities` WRITE;
/*!40000 ALTER TABLE `authorities` DISABLE KEYS */;
INSERT INTO `authorities` VALUES (1,'CCE','http://onlinebooks.library.upenn.edu/cce',NULL),
  (3,'CRMS Historical','crms?p=adminHistoricalReviews;search1value=__HTID__','r'),
  (5,'HathiTrust','https://__HATHITRUST__/cgi/pt?debug=supercalifragilisticexpialidocious;id=__HTID__;skin=crms;page=root;seq=1;view=__VIEW__;size=__MAG__','h'),
  (7,'Jira','https://wush.net/jira/hathitrust/browse/__TICKET__','j'),
  (15,'Stanford','crms?p=stanford&field=search_author&q=__AUTHOR__',NULL),
  (17,'Stanford Everything','crms?p=stanford&field=search&q=__AUTHOR__ __TITLE__','q'),
  (19,'Stanford Author','crms?p=stanford&field=search_author&q=__AUTHOR__','a'),
  (21,'Stanford Title','crms?p=stanford&field=search&q=__TITLE__','t'),
  (23,'Summary','inserts?p=insertsSummary;id=__HTID__;user=__USER__',NULL),
  (25,'Table of Dates','inserts?p=insertsTable',NULL),
  (27,'USCC','http://cocatalog.loc.gov/cgi-bin/Pwebrecon.cgi?DB=local&PAGE=First',NULL),
  (29,'VIAF','https://viaf.org/viaf/search?query=local.personalNames+all+%22__AUTHOR__%22&stylesheet=/viaf/xsl/results.xsl&sortKeys=holdingscount&maximumRecords=100','v'),
  (31,'Zephir MARC','https://catalog.hathitrust.org/Record/__SYSID__.marc','z'),
  (33,'Wikipedia','https://en.wikipedia.org/wiki/Special:Search?search=__AUTHOR__','w'),
  (35,'HT Thumbnail','https://__HATHITRUST__/cgi/pt?debug=supercalifragilisticexpialidocious;id=__HTID__;skin=crms;page=root;seq=1;view=thumb',NULL),
  (37,'Page Image','https://__HATHITRUST__/cgi/imgsrv/image?debug=supercalifragilisticexpialidocious;id=__HTID__;seq=1',NULL),
  (39,'AMICUS','http://amicus.collectionscanada.ca/aaweb-bin/aamain/rqst_sb?l=0&r=0&lvl=3&v=1&bill=1&username=NLCGUEST&documentName=anon&t=NA+__AUTHOR__',NULL),
  (41,'Archives Canada','http://www.collectionscanada.gc.ca/lac-bac/results/anc?form=anc_simple&lang=eng&FormName=Ancestors+Simple+Search&Language=eng&Sources=genapp&SearchIn_1=&SearchInText_1=__AUTHOR__&soundex=on',NULL),
  (43,'AustLit','http://www.austlit.edu.au/austlit/search/page?query=__AUTHOR__',NULL),
  (45,'Australian Biography','http://adb.anu.edu.au/biographies/search/?scope=person&query=__AUTHOR_F__',NULL),
  (47,'Canadian Biography','http://www.biographi.ca/009004-110.01-e.php?q2=__AUTHOR__&amp;partial=on',NULL),
  (49,'COPAC','http://copac.ac.uk/search?au=__AUTHOR__&sort-order=date',NULL),
  (51,'Historical Reviews','crms?p=adminHistoricalReviews;sys=crmsworld;search1=Author;search1value=__AUTHOR__;order=Date;dir=DESC',NULL),
  (53,'LoC Authorities','http://id.loc.gov/search/?q=__AUTHOR__&q=cs%3Ahttp%3A%2F%2Fid.loc.gov%2Fauthorities%2Fnames',NULL),
  (57,'NGCOBA','http://www.authorandbookinfo.com/ngcoba/__AUTHOR_2__.htm',NULL),
  (59,'NLoA','http://catalogue.nla.gov.au/Search/Home?lookfor=__AUTHOR__&type=author&limit[]=&submit=Find',NULL),
  (61,'Obituaries Australian','http://oa.anu.edu.au/obituaries/search/?scope=person&query=__AUTHOR_F__',NULL),
  (63,'Volume Tracking','crms?p=track;query=__HTID__',NULL),
  (65,'MARC Country Codes','/crms/web/marc_country_codes.html',NULL);
/*!40000 ALTER TABLE `authorities` ENABLE KEYS */;
UNLOCK TABLES;

