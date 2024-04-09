use crms;

LOCK TABLES `institutions` WRITE;
/*!40000 ALTER TABLE `institutions` DISABLE KEYS */;
INSERT INTO `institutions` VALUES (0,'University of Michigan','UM','umich.edu',0);
/*!40000 ALTER TABLE `institutions` ENABLE KEYS */;
UNLOCK TABLES;
