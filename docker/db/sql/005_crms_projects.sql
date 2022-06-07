use crms;

LOCK TABLES `projects` WRITE;
/*!40000 ALTER TABLE `projects` DISABLE KEYS */;
INSERT INTO `projects` VALUES (1,'Core','ff8000',800,0,1,0,5,21),
  (3,'Special','ed206e',0,0,0,0,5,7),
  (5,'State Gov Docs','7fe8d9',0,0,1,0,5,21),
  (7,'MDP Corrections','d596e3',0,0,0,0,5,21),
  (9,'Frontmatter','90bbde',0,0,0,1,37,35),
  (11,'Commonwealth','ff8000',0,0,0,0,5,29),
  (13,'CRMS Spain','ffff00',0,0,0,0,5,29),
  (15,'US Renewal','80ff80',0,1,0,0,5,29),
  (17,'New Year','b1b2df',0,1,1,0,5,29),
  (19,'Crown Copyright','000000',800,0,1,0,5,63),
  (21,'Publication Date','006ff4',800,0,0,0,5,65);
/*!40000 ALTER TABLE `projects` ENABLE KEYS */;
UNLOCK TABLES;
