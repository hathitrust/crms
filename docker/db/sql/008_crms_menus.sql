USE crms;

LOCK TABLES `menus` WRITE;
/*!40000 ALTER TABLE `menus` DISABLE KEYS */;
INSERT INTO `menus` VALUES (0,'Review','minor',NULL,0,NULL),
  (1,'Search/Browse','major',NULL,1,NULL),
  (2,'Documentation','total',NULL,2,1),
  (3,'Stats/Reports','orange',NULL,3,NULL),
  (4,'Administrative','red',NULL,4,NULL);
/*!40000 ALTER TABLE `menus` ENABLE KEYS */;
UNLOCK TABLES;
