USE crms;

LOCK TABLES `menuitems` WRITE;
/*!40000 ALTER TABLE `menuitems` DISABLE KEYS */;
INSERT INTO `menuitems` VALUES
  (0,'review','crms?p=review','review','r',NULL,0),
  (0,'provisional_matches','crms?p=provisionals','undReviews','e',NULL,1),
  (0,'conflicts','crms?p=conflicts','expert','e',NULL,2),
  (0,'my_unprocessed_reviews','crms?p=editReviews','editReviews','r',NULL,3),
  (0,'my_held_reviews','crms?p=holds','holds','r',NULL,4),
  (0,'automatic_rights_inheritance','crms?p=inherit;auto=1','inherit','ea',NULL,5),
  (0,'rights_inheritance_pending_approval','crms?p=inherit;auto=0','inherit','ea',NULL,6),
  (1,'historical_reviews','crms?p=adminHistoricalReviews','adminHistoricalReviews',NULL,NULL,0),
  (1,'active_reviews','crms?p=adminReviews','adminReviews','eax',NULL,1),
  (1,'all_held_reviews','crms?p=adminHolds','adminHolds','ea',NULL,2),
  (1,'queue','/crms/queue','queue','ea',NULL,3),
  (1,'final_determinations','crms?p=exportData','exportData','ea',NULL,4),
  (1,'candidates','crms?p=candidates','candidates','ea',NULL,5),
  (1,'filtered_volumes','crms?p=und','und','ea',NULL,6),
  (2,'crms_documentation','https://www.hathitrust.org/CRMSdocumentation',NULL,NULL,'_blank',1),
  (2,'review_search_help','/crms/web/pdf/ReviewSearchHelp.pdf',NULL,NULL,'_blank',7),
  (2,'review_search_terms','/crms/web/pdf/ReviewSearchTerms.pdf',NULL,NULL,'_blank',8),
  (2,'user_levels_privileges','/crms/web/pdf/UserLevelsPrivileges.pdf',NULL,'a','_blank',12),
  (2,'system_generated_reviews','/crms/web/pdf/SystemGeneratedReviews.pdf',NULL,'a','_blank',14),
  (2,'crms_status_codes','/crms/web/pdf/CRMSStatusCodes.pdf',NULL,'a','_blank',15),
  (3,'my_review_stats','crms?p=userRate','userRate','r',NULL,1),
  (3,'all_review_stats','crms?p=adminUserRate','adminUserRate','ea',NULL,2),
  (3,'system_summary','crms?p=queueStatus','queueStatus','ea',NULL,8),
  (3,'export_stats','crms?p=exportStats','exportStats','ea',NULL,9),
  (3,'progress_dashboard','crms?p=dashboard','dashboard',NULL,'_blank',10),
  (3,'reviewer_activity','crms?p=reviewerActivity','reviewerActivity','ea',NULL,11),
  (4,'user_accounts','/crms/users','adminUser','eai',NULL,1),
  (4,'institutions','crms?p=institutions','institutions','a',NULL,2),
  (4,'query_rights_database','crms?p=rights','rights',NULL,NULL,3),
  (4,'track_tolumes','crms?p=track','track',NULL,NULL,4),
  (4,'all_locked_volumes','crms?p=adminQueue','adminQueue','ea',NULL,5),
  (4,'add_to_queue','/crms/queue/new','queueAdd','ea',NULL,6),
  (4,'set_system_status','crms?p=systemStatus','systemStatus','ea',NULL,7),
  (4,'system_administration','crms?p=debug','debug','s',NULL,8),
  (4,'projects','crms?p=projects','projects','a',NULL,9),
  (4,'keio_data','crms?p=keio','keio','a',NULL,10),
  (4,'licensing','crms?p=licensing','licensing','a',NULL,11);
/*!40000 ALTER TABLE `menuitems` ENABLE KEYS */;
UNLOCK TABLES;
