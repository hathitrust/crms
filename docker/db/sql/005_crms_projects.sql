use crms;

LOCK TABLES `projects` WRITE;
/*!40000 ALTER TABLE `projects` DISABLE KEYS */;
INSERT INTO `projects` VALUES (1,'Core',NULL,800,0,1,0,5,21),
  (3,'Special',NULL,0,0,0,0,5,7),
  (5,'State Gov Docs',NULL,0,0,1,0,5,21),
  (7,'MDP Corrections',NULL,0,0,0,0,5,21),
  (9,'Frontmatter',NULL,0,0,0,1,37,35),
  (11,'Commonwealth',NULL,0,0,0,0,5,29),
  (13,'CRMS Spain',NULL,0,0,0,0,5,29),
  (15,'US Renewal',NULL,0,1,0,0,5,29),
  (17,'New Year',NULL,0,1,1,0,5,29),
  (19,'Crown Copyright',NULL,800,0,1,0,5,63),
  (21,'Publication Date',NULL,800,0,0,0,5,65);
/*!40000 ALTER TABLE `projects` ENABLE KEYS */;
UNLOCK TABLES;

