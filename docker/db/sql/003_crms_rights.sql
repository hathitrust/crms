use crms;

LOCK TABLES `rights` WRITE;
/*!40000 ALTER TABLE `rights` DISABLE KEYS */;
INSERT INTO `rights` VALUES (1,1,7,'public domain/copyright was not renewed'),
(2,1,9,'public domain/copyright date is pre-US copyright period'),
(3,1,2,'public domain/no copyright notice'),
(4,2,7,'in copyright/copyright was renewed'),
(5,2,9,'in copyright/copyright date is pre-US copyright period'),
(6,5,8,'undetermined/needs further investigation'),
(7,9,9,'public domain in the US/copyright date is pre-US copyright period'),
(8,1,14,NULL),
(9,1,15,NULL),
(14,1,13,NULL),
(15,2,13,NULL),
(16,5,13,NULL),
(17,9,2,'public domain in the US/no copyright notice'),
(18,9,14,'public domain in the US/publication date* on piece is pre-1923 (US work)'),
(19,9,7,'public domain in the US/copyright was not renewed'),
(21,9,13,NULL),
(22,2,14,'in copyright/copyright was renewed'),
(23,19,17,'in-copyright in the US/GATT-restored (pd in country of origin)'),
(24,5,7,'overall volume is public domain due to no renewal/has inserts'),
(25,19,7,NULL);
/*!40000 ALTER TABLE `rights` ENABLE KEYS */;
UNLOCK TABLES;
