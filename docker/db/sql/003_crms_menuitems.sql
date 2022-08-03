USE crms;

LOCK TABLES `menuitems` WRITE;
/*!40000 ALTER TABLE `menuitems` DISABLE KEYS */;
INSERT INTO `menuitems` VALUES
  (0,'Review','crms?p=review','review','r',NULL,0),
  (0,'Provisional Matches','crms?p=provisionals','undReviews','e',NULL,1),
  (0,'Conflicts','crms?p=conflicts','expert','e',NULL,2),
  (0,'My Unprocessed Reviews','crms?p=editReviews','editReviews','r',NULL,3),
  (0,'My Held Reviews','crms?p=holds','holds','r',NULL,4),
  (0,'Automatic Rights Inheritance','crms?p=inherit;auto=1','inherit','ea',NULL,5),
  (0,'Rights Inheritance Pending Approval','crms?p=inherit;auto=0','inherit','ea',NULL,6),
  (1,'Historical Reviews','crms?p=adminHistoricalReviews','adminHistoricalReviews',NULL,NULL,0),
  (1,'Active Reviews','crms?p=adminReviews','adminReviews','eax',NULL,1),
  (1,'All Held Reviews','crms?p=adminHolds','adminHolds','ea',NULL,2),
  (1,'Volumes in Queue','crms?p=queue','queue','ea',NULL,3),
  (1,'Final Determinations','crms?p=exportData','exportData','ea',NULL,4),
  (1,'Candidates','crms?p=candidates','candidates','ea',NULL,5),
  (1,'Filtered Volumes','crms?p=und','und','ea',NULL,6),
  (2,'CRMS Documentation','https://www.hathitrust.org/CRMSdocumentation',NULL,NULL,'_blank',1),
  (2,'Review Search Help','/crms/web/pdf/ReviewSearchHelp.pdf',NULL,NULL,'_blank',7),
  (2,'Review Search Terms','/crms/web/pdf/ReviewSearchTerms.pdf',NULL,NULL,'_blank',8),
  (2,'User Levels/Privileges','/crms/web/pdf/UserLevelsPrivileges.pdf',NULL,'a','_blank',12),
  (2,'System Generated Reviews','/crms/web/pdf/SystemGeneratedReviews.pdf',NULL,'a','_blank',14),
  (2,'CRMS Status Codes','/crms/web/pdf/CRMSStatusCodes.pdf',NULL,'a','_blank',15),
  (3,'My Review Stats','crms?p=userRate','userRate','r',NULL,1),
  (3,'All Review Stats','crms?p=adminUserRate','adminUserRate','ea',NULL,2),
  (3,'System Summary','crms?p=queueStatus','queueStatus','ea',NULL,8),
  (3,'Export Stats','crms?p=exportStats','exportStats','ea',NULL,9),
  (3,'Progress Dashboard','crms?p=dashboard','dashboard',NULL,'_blank',10),
  (3,'Reviewer Activity','crms?p=reviewerActivity','reviewerActivity','ea',NULL,11),
  (4,'User Accounts','/crms/users','adminUser','eai',NULL,1),
  (4,'Institutions','crms?p=institutions','institutions','a',NULL,2),
  (4,'Query Rights Database','crms?p=rights','rights',NULL,NULL,3),
  (4,'Track Volumes','crms?p=track','track',NULL,NULL,4),
  (4,'All Locked Volumes','crms?p=adminQueue','adminQueue','ea',NULL,5),
  (4,'Add to Queue','crms?p=queueAdd','queueAdd','ea',NULL,6),
  (4,'Set System Status','crms?p=systemStatus','systemStatus','ea',NULL,7),
  (4,'System Administration','crms?p=debug','debug','s',NULL,8),
  (4,'Projects','crms?p=projects','projects','a',NULL,9),
  (4,'Keio Data','crms?p=keio','keio','a',NULL,10),
  (4,'Licensing','crms?p=licensing','licensing','a',NULL,11);
/*!40000 ALTER TABLE `menuitems` ENABLE KEYS */;
UNLOCK TABLES;
