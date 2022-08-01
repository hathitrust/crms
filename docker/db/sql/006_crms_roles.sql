use crms;

LOCK TABLES `roles` WRITE;
/*!40000 ALTER TABLE `roles` DISABLE KEYS */;
INSERT INTO `roles` VALUES (1,'Reviewer'),
  (2,'Expert');
/*!40000 ALTER TABLE `roles` ENABLE KEYS */;
UNLOCK TABLES;
