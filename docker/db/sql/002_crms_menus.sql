USE crms;

LOCK TABLES `menus` WRITE;
/*!40000 ALTER TABLE `menus` DISABLE KEYS */;
INSERT INTO `menus` VALUES (0,'review','minor',NULL,0,NULL),
  (1,'search_browse','major',NULL,1,NULL),
  (2,'documentation','total',NULL,2,1),
  (3,'stats_reports','orange',NULL,3,NULL),
  (4,'administrative','red',NULL,4,NULL);
/*!40000 ALTER TABLE `menus` ENABLE KEYS */;
UNLOCK TABLES;
