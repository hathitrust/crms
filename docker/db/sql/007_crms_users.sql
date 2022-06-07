use crms;

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
INSERT INTO `users` VALUES (1,'autocrms','autocrms',0,0,0,0,NULL,NULL,'umich',NULL,NULL,1,1),
  (2,'rereport01','rereport01',0,0,0,0,NULL,NULL,'umich',NULL,NULL,1,1),
  (3,'rereport02','rereport02',0,0,0,0,NULL,NULL,'umich',NULL,NULL,1,1),
  (4,'rereport03','rereport03',0,0,0,0,NULL,NULL,'umich',NULL,NULL,1,1),
  (5,'rereport04','rereport04',0,0,0,0,NULL,NULL,'umich',NULL,NULL,1,1),
  (6,'rereport05','rereport05',0,0,0,0,NULL,NULL,'umich',NULL,NULL,1,1),
  (7,'schuster6695@umich.edu','Aurelia Parisian MD',1,1,1,1,NULL,NULL,'umich',NULL,NULL,1,0),
  (8,'padberg5560@umich.edu','Bo Mraz',1,1,1,1,NULL,NULL,'umich',NULL,NULL,1,0),
  (9,'robel6407@umich.edu','Soledad Heathcote',1,1,1,1,NULL,NULL,'umich',NULL,NULL,1,0),
  (10,'koepp5559@umich.edu','Chris Grimes',0,0,0,1,NULL,NULL,'umich',NULL,NULL,1,0),
  (11,'haley5542@umich.edu','Isaac Daugherty',0,0,0,1,NULL,NULL,'umich',NULL,NULL,1,0),
  (12,'kemmer805@umich.edu','Demarcus Rodriguez I',0,0,0,1,NULL,NULL,'umich',NULL,NULL,1,0),
  (13,'runolfsdottir4365@umn.edu','Ruthie Gulgowski',1,1,1,0,NULL,NULL,'umn',NULL,NULL,1,0),
  (14,'wolff8668@ucop.edu','Fredy Bogisich',1,1,1,0,NULL,NULL,'ucop',NULL,NULL,1,0),
  (15,'jerde8826@psu.edu','Furman Bins',1,1,1,0,NULL,NULL,'psu',NULL,NULL,1,0),
  (16,'lueilwitz4206@umich.edu','Jacquelyn Satterfield',1,1,1,0,NULL,NULL,'umich',NULL,NULL,1,0),
  (17,'gislason7214@wvu.edu','Darrell Murphy',1,1,1,0,NULL,NULL,'wvu',NULL,NULL,1,0),
  (18,'wisoky4948@psu.edu','Alexzander West',1,1,0,0,NULL,NULL,'psu',NULL,NULL,1,0),
  (19,'little7680@lafayette.edu','Hattie Mante',1,1,0,0,NULL,NULL,'lafayette',0.1500,NULL,1,0),
  (20,'cruickshank9169@mcmaster.ca','Loyce Champlin',1,1,0,0,NULL,NULL,'mcmaster',NULL,NULL,1,0),
  (21,'emmerich515@ucsc.edu','Kurtis Deckow',1,1,0,0,NULL,NULL,'ucsc',NULL,NULL,1,0),
  (22,'bayer8871@txstate.edu','Clint Bartell',1,1,0,0,NULL,NULL,'txstate',0.1500,NULL,1,0),
  (23,'schmidt8302@bc.edu','Bell Bauch',1,1,0,0,NULL,NULL,'bc',0.2000,NULL,1,0),
  (24,'doyle6459@nd.edu','Abdullah Schowalter',1,1,0,0,NULL,NULL,'nd',0.1500,NULL,1,0),
  (25,'lemke5822@umich.edu','Miss Harmony Stamm',1,1,0,0,NULL,NULL,'umich',NULL,NULL,1,0),
  (26,'gaylord217@wfu.edu','Annalise Sanford',1,1,0,0,NULL,NULL,'wfu',0.0750,NULL,1,0),
  (27,'welch1123@ucsc.edu','Julius Turcotte Jr.',1,1,0,0,NULL,NULL,'ucsc',NULL,NULL,1,0),
  (28,'carter1378@duke.edu','Kara Heller',1,1,0,0,NULL,NULL,'duke',0.1500,NULL,1,0),
  (29,'stracke6201@txstate.edu','Vita Schiller',1,1,0,0,NULL,NULL,'txstate',0.0750,NULL,1,0),
  (30,'feest9034@mcgill.ca','Jenifer Yost',1,1,0,0,NULL,NULL,'mcgill',0.2000,NULL,1,0),
  (31,'homenick9236@umass.edu','Jarrod Aufderhar',1,1,0,0,NULL,NULL,'umass',0.0750,NULL,1,0),
  (32,'witting5665@ucla.edu','Louvenia Koch',1,1,0,0,NULL,NULL,'ucla',0.1500,NULL,1,0),
  (33,'doyle7981@umich.edu','Dr. Deondre Hintz',1,1,0,0,NULL,NULL,'umich',NULL,NULL,1,0),
  (34,'fahey6687@umich.edu','Suzanne Hagenes',1,1,0,0,NULL,NULL,'umich',NULL,NULL,1,0),
  (35,'yost163@psu.edu','Arlo Rutherford',1,1,0,0,NULL,NULL,'psu',0.0750,NULL,1,0),
  (36,'wolf4554@mcmaster.ca','Ms. Marilyne Stark',1,1,0,0,NULL,NULL,'mcmaster',NULL,NULL,1,0),
  (37,'gorczany7999@temple.edu','Kailyn Deckow',1,1,0,0,NULL,NULL,'temple',0.0750,NULL,1,0),
  (38,'dare5310@uky.edu','Gladyce Maggio',1,1,0,0,NULL,NULL,'uky',NULL,NULL,1,0),
  (39,'kiehn2242@ualberta.ca','Mr. Vern Auer',1,1,0,0,NULL,NULL,'ualberta',NULL,NULL,1,0),
  (40,'cartwright2134@duke.edu','Kristofer Block',1,1,0,0,NULL,NULL,'duke',NULL,NULL,1,0),
  (41,'ebert1353@ucsd.edu','Sheridan Ledner DDS',1,1,0,0,NULL,NULL,'ucsd',NULL,NULL,1,0),
  (42,'prohaska1917@mcgill.ca','Joseph Nicolas',1,1,0,0,NULL,NULL,'mcgill',NULL,NULL,1,0),
  (43,'emmerich2326@ualberta.ca','Dewayne Wunsch',1,1,0,0,NULL,NULL,'ualberta',NULL,NULL,1,0),
  (44,'bednar4350@unc.edu','Eileen Herzog',1,1,0,0,NULL,NULL,'unc',0.1500,NULL,1,0),
  (45,'aufderhar520@duke.edu','Pierce Fritsch Sr.',1,0,0,0,NULL,NULL,'duke',NULL,NULL,1,0),
  (46,'marks2496@illinois.edu','Ms. Alene Johns',1,0,0,0,NULL,NULL,'illinois',0.1500,NULL,1,0),
  (47,'gulgowski4555@psu.edu','Mckenna Sporer',1,0,0,0,NULL,NULL,'psu',NULL,NULL,1,0),
  (48,'jakubowski4366@osu.edu','Bret Simonis',0,0,0,0,NULL,NULL,'osu',0.2500,NULL,0,0),
  (49,'hickle1189@nyu.edu','Lawrence Ullrich',0,0,0,0,NULL,NULL,'nyu',0.0750,NULL,0,0),
  (50,'wilderman3994@psu.edu','Dr. Alana Hahn',0,0,0,0,NULL,NULL,'psu',0.1500,NULL,0,0),
  (51,'collier6456@umd.edu','Nya Kuhic',0,0,0,0,NULL,NULL,'umd',0.1000,NULL,0,0),
  (52,'moore2923@duke.edu','Landen Batz',0,0,0,0,NULL,NULL,'duke',0.2000,NULL,0,0),
  (53,'baumbach9867@depaul.edu','Kim Nicolas',0,0,0,0,NULL,NULL,'depaul',0.1500,NULL,0,0),
  (54,'jacobs1786@osu.edu','Carlee Eichmann',0,0,0,0,NULL,NULL,'osu',0.2500,NULL,0,0),
  (55,'little4496@ucop.edu','Seth Moore',0,0,0,0,NULL,NULL,'ucop',0.2500,NULL,0,0),
  (56,'huels2256@queensu.ca','Chelsey Heathcote',0,0,0,0,NULL,NULL,'queensu',NULL,NULL,0,0),
  (57,'dibbert5082@wisc.edu','Hallie Bernhard',0,0,0,0,NULL,NULL,'wisc',NULL,NULL,0,0),
  (58,'leffler7877@wisc.edu','Colin Beer',0,0,0,0,NULL,NULL,'wisc',NULL,NULL,0,0),
  (59,'senger3087@wisc.edu','Chester Schiller',0,0,0,0,NULL,NULL,'wisc',NULL,NULL,0,0),
  (60,'o\'hara237@wisc.edu','Dr. Nathen Kuhic',0,0,0,0,NULL,NULL,'wisc',NULL,NULL,0,0),
  (61,'stracke7134@wisc.edu','Clair Schmitt',0,0,0,0,NULL,NULL,'wisc',NULL,NULL,0,0),
  (62,'zboncak113@wisc.edu','Furman Doyle',0,0,0,0,NULL,NULL,'wisc',NULL,NULL,0,0),
  (63,'schowalter2727@umn.edu','Jeffery Lemke',0,0,0,0,NULL,NULL,'umn',NULL,NULL,0,0),
  (64,'wehner5128@umn.edu','Creola Waelchi',0,0,0,0,NULL,NULL,'umn',NULL,NULL,0,0),
  (65,'pagac7177@umn.edu','Alfreda Fadel',0,0,0,0,NULL,NULL,'umn',NULL,NULL,0,0),
  (66,'macejkovic7325@umn.edu','Flo Murazik',0,0,0,0,NULL,NULL,'umn',NULL,NULL,0,0),
  (67,'cole7329@umn.edu','Keanu White',0,0,0,0,NULL,NULL,'umn',NULL,NULL,0,0),
  (68,'boehm1274@umn.edu','Darren O\'Reilly',0,0,0,0,NULL,NULL,'umn',NULL,NULL,0,0),
  (69,'haag3787@umn.edu','Kade Lesch',0,0,0,0,NULL,NULL,'umn',NULL,NULL,0,0),
  (70,'powlowski5852@umn.edu','Kory Gorczany',0,0,0,0,NULL,NULL,'umn',NULL,NULL,0,0),
  (71,'rosenbaum6387@umd.edu','Aracely Pfeffer',0,0,0,0,NULL,NULL,'umd',NULL,NULL,0,0),
  (72,'ledner1725@wsu.edu','Henderson Rice',0,0,0,0,NULL,NULL,'wsu',0.0750,NULL,0,0),
  (73,'rice9933@ucsc.edu','Penelope Dickens I',0,0,0,0,NULL,NULL,'ucsc',0.1500,NULL,0,0),
  (74,'conn7045@ubc.ca','Russell Yost',0,0,0,0,NULL,NULL,'ubc',NULL,NULL,0,0),
  (75,'harris3702@ubc.ca','Mr. Quincy Crooks',0,0,0,0,NULL,NULL,'ubc',NULL,NULL,0,0),
  (76,'o\'conner8535@northwestern.edu','Madelynn Monahan III',0,0,0,0,NULL,NULL,'northwestern',0.0500,NULL,0,0),
  (77,'corkery7187@upenn.edu','Lon Klein',0,0,0,0,NULL,NULL,'upenn',0.0750,NULL,0,0),
  (78,'luettgen868@ualberta.ca','Estevan Gleichner',0,0,0,0,NULL,NULL,'ualberta',NULL,NULL,0,0),
  (79,'roberts5217@illinois.edu','Emma Kautzer',0,0,0,0,NULL,NULL,'illinois',0.0500,NULL,0,0),
  (80,'hoeger1959@umich.edu','Luz DuBuque',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (81,'ferry902@dartmouth.edu','Brenden Olson',0,0,0,0,NULL,NULL,'dartmouth',NULL,NULL,0,0),
  (82,'smith6248@iu.edu','Leola Russel DVM',0,0,0,0,NULL,NULL,'iu',0.1500,NULL,0,0),
  (83,'mcdermott4578@illinois.edu','Melvina Bartell III',0,0,0,0,NULL,NULL,'illinois',0.5000,NULL,0,0),
  (84,'herzog7059@umich.edu','Anjali Legros',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (85,'rowe626@umn.edu','Jasmin Heidenreich',0,0,0,0,NULL,NULL,'umn',0.2000,NULL,0,0),
  (86,'hills7986@ualberta.ca','Marlen Wuckert',0,0,0,0,NULL,NULL,'ualberta',NULL,NULL,0,0),
  (87,'rowe4893@columbia.edu','Michelle Rempel',0,0,0,0,NULL,NULL,'columbia',0.1500,NULL,0,0),
  (88,'kessler2351@psu.edu','Guadalupe Windler MD',0,0,0,0,NULL,NULL,'psu',0.1100,NULL,0,0),
  (89,'cummings726@columbia.edu','Colten Gleason',0,0,0,0,NULL,NULL,'columbia',NULL,NULL,0,0),
  (90,'lockman9102@umich.edu','Alfreda Muller',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (91,'grimes4502@columbia.edu','Quentin Terry',0,0,0,0,NULL,NULL,'columbia',0.1500,NULL,0,0),
  (92,'cronin2616@duke.edu','Gwendolyn Mills',0,0,0,0,NULL,NULL,'duke',NULL,NULL,0,0),
  (93,'ratke9760@umich.edu','Heber Murray',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (94,'ruecker5604@baylor.edu','Kade Balistreri Sr.',0,0,0,0,NULL,NULL,'baylor',0.1200,NULL,0,0),
  (95,'senger1905@utk.edu','Luther Murray',0,0,0,0,NULL,NULL,'utk',0.0750,NULL,0,0),
  (96,'tromp4562@umich.edu','Ottis Pouros',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (97,'marks2354@pitt.edu','Maegan Gleichner',0,0,0,0,NULL,NULL,'pitt',NULL,NULL,0,0),
  (98,'swift6738@umd.edu','Michele Yundt DVM',0,0,0,0,NULL,NULL,'umd',0.1000,NULL,0,0),
  (99,'walsh7989@osu.edu','Davion Kutch',0,0,0,0,NULL,NULL,'osu',0.2500,NULL,0,0),
  (100,'walter5066@umich.edu','Vinnie Schroeder',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (101,'gibson7867@iu.edu','Nathaniel Deckow',0,0,0,0,NULL,NULL,'iu',0.0500,NULL,0,0),
  (102,'terry3452@upenn.edu','Graham Reinger',0,0,0,0,NULL,NULL,'upenn',0.0750,NULL,0,0),
  (103,'murazik3875@ucop.edu','Jazmyn Hackett',0,0,0,0,NULL,NULL,'ucop',0.2000,NULL,0,0),
  (104,'ziemann9036@mcmaster.ca','Dr. Lillie Rosenbaum',0,0,0,0,NULL,NULL,'mcmaster',NULL,NULL,0,0),
  (105,'lemke2497@ou.edu','Miss Triston Hudson',0,0,0,0,NULL,NULL,'ou',NULL,NULL,0,0),
  (106,'roberts7519@cornell.edu','Jarrett Murphy',0,0,0,0,NULL,NULL,'cornell',0.1000,NULL,0,0),
  (107,'renner2745@cornell.edu','Jany Corkery',0,0,0,0,NULL,NULL,'cornell',0.0750,NULL,0,0),
  (108,'pagac851@wisc.edu','Mr. Adolfo Kris',0,0,0,0,NULL,NULL,'wisc',NULL,NULL,0,0),
  (109,'muller7610@umn.edu','Luella Bosco DDS',0,0,0,0,NULL,NULL,'umn',0.2000,NULL,0,0),
  (110,'kling5802@psu.edu','Valentina Rosenbaum',0,0,0,0,NULL,NULL,'psu',NULL,NULL,0,0),
  (111,'gusikowski2778@amherst.edu','Gabe Aufderhar',0,0,0,0,NULL,NULL,'amherst',0.1800,NULL,0,0),
  (112,'o\'reilly6557@princeton.edu','Rhoda Jacobs',0,0,0,0,NULL,NULL,'princeton',NULL,NULL,0,0),
  (113,'dickens3498@ucla.edu','Pearlie Shields',0,0,0,0,NULL,NULL,'ucla',0.0500,NULL,0,0),
  (114,'anderson7953@umn.edu','Albertha Murazik',0,0,0,0,NULL,NULL,'umn',0.1500,NULL,0,0),
  (115,'gerhold6851@psu.edu','Cortez Hegmann',0,0,0,0,NULL,NULL,'psu',0.0750,NULL,0,0),
  (116,'ortiz214@osu.edu','Stephanie Will',0,0,0,0,NULL,NULL,'osu',0.0750,NULL,0,0),
  (117,'walsh5741@ucsc.edu','Gladyce Bednar I',0,0,0,0,NULL,NULL,'ucsc',NULL,NULL,0,0),
  (118,'brown9603@umich.edu','Misty Grant',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (119,'considine1325@wisc.edu','Trever Schneider',0,0,0,0,NULL,NULL,'wisc',NULL,NULL,0,0),
  (120,'boyle4527@umn.edu','Kayla O\'Kon V',0,0,0,0,NULL,NULL,'umn',NULL,NULL,0,0),
  (121,'senger6915@illinois.edu','Maria Maggio',0,0,0,0,NULL,NULL,'illinois',0.1500,NULL,0,0),
  (122,'wehner5719@mcgill.ca','Sofia Gislason',0,0,0,0,NULL,NULL,'mcgill',0.2000,NULL,0,0),
  (123,'denesik2459@dartmouth.edu','Alda Krajcik',0,0,0,0,NULL,NULL,'dartmouth',NULL,NULL,0,0),
  (124,'larkin1100@umd.edu','Rodolfo Robel MD',0,0,0,0,NULL,NULL,'umd',0.1000,NULL,0,0),
  (125,'skiles2509@unc.edu','Ezra Harris',0,0,0,0,NULL,NULL,'unc',0.1000,NULL,0,0),
  (126,'trantow2710@wsu.edu','Jeramy Dietrich',0,0,0,0,NULL,NULL,'wsu',0.1500,NULL,0,0),
  (127,'skiles8982@unc.edu','Mercedes Gerlach',0,0,0,0,NULL,NULL,'unc',0.2000,NULL,0,0),
  (128,'o\'reilly6875@umd.edu','Kyla Greenholt',0,0,0,0,NULL,NULL,'umd',0.1000,NULL,0,0),
  (129,'konopelski5191@umn.edu','Ms. Freddie Crona',0,0,0,0,NULL,NULL,'umn',NULL,NULL,0,0),
  (130,'cruickshank2874@tamu.edu','Ernest Becker',0,0,0,0,NULL,NULL,'tamu',0.0750,NULL,0,0),
  (131,'veum1739@gsu.edu','Alyson Eichmann',0,0,0,0,NULL,NULL,'gsu',0.1500,NULL,0,0),
  (132,'heathcote9592@umich.edu','Ellsworth Ondricka',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (133,'wolff2183@stanford.edu','Giovanni Pagac',0,0,0,0,NULL,NULL,'stanford',NULL,NULL,0,0),
  (134,'witting4397@utk.edu','Sheila Collins',0,0,0,0,NULL,NULL,'utk',0.0750,NULL,0,0),
  (135,'schoen231@ualberta.ca','Thalia Jacobi',0,0,0,0,NULL,NULL,'ualberta',NULL,NULL,0,0),
  (136,'langworth3805@uci.edu','Payton Wunsch',0,0,0,0,NULL,NULL,'uci',NULL,NULL,0,0),
  (137,'hodkiewicz7592@ucsd.edu','Elyssa Eichmann',0,0,0,0,NULL,NULL,'ucsd',NULL,NULL,0,0),
  (138,'borer6029@psu.edu','Trisha Graham',0,0,0,0,NULL,NULL,'psu',0.0750,NULL,0,0),
  (139,'hermiston8892@jhu.edu','Kay Hudson',0,0,0,0,NULL,NULL,'jhu',0.2500,NULL,0,0),
  (140,'fay552@northwestern.edu','Zakary Cartwright',0,0,0,0,NULL,NULL,'northwestern',0.0500,NULL,0,0),
  (141,'hintz9240@dartmouth.edu','Leanna Robel',0,0,0,0,NULL,NULL,'dartmouth',0.1000,NULL,0,0),
  (142,'gutkowski2928@columbia.edu','Miss Orin Gutmann',0,0,0,0,NULL,NULL,'columbia',0.5000,NULL,0,0),
  (143,'zulauf9354@umich.edu','Kelly Ruecker',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (144,'hamill9826@ucsf.edu','Junior Crist',0,0,0,0,NULL,NULL,'ucsf',NULL,NULL,0,0),
  (145,'mayert7985@dartmouth.edu','Wilfred Hirthe',0,0,0,0,NULL,NULL,'dartmouth',NULL,NULL,0,0),
  (146,'cummings2504@stanford.edu','Braeden Schaefer',0,0,0,0,NULL,NULL,'stanford',0.5000,NULL,0,0),
  (147,'stamm9602@umich.edu','Mr. Wilbert Halvorson',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (148,'schulist5823@duke.edu','Reuben Little',0,0,0,0,NULL,NULL,'duke',0.1500,NULL,0,0),
  (149,'dicki1506@illinois.edu','Vicky Emmerich',0,0,0,0,NULL,NULL,'illinois',0.1750,NULL,0,0),
  (150,'kshlerin7792@psu.edu','Jedidiah Hand',0,0,0,0,NULL,NULL,'psu',0.1500,NULL,0,0),
  (151,'wintheiser4417@umich.edu','Isadore Terry',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (152,'rippin48@ufl.edu','Jocelyn Weimann',0,0,0,0,NULL,NULL,'ufl',0.0750,NULL,0,0),
  (153,'baumbach6618@umass.edu','Sharon Ebert',0,0,0,0,NULL,NULL,'umass',0.0750,NULL,0,0),
  (154,'stokes3833@northwestern.edu','Alysha D\'Amore',0,0,0,0,NULL,NULL,'northwestern',0.0500,NULL,0,0),
  (155,'adams7698@pitt.edu','Isom Hansen',0,0,0,0,NULL,NULL,'pitt',0.1000,NULL,0,0),
  (156,'cartwright7819@umd.edu','Patsy Tillman',0,0,0,0,NULL,NULL,'umd',NULL,NULL,0,0),
  (157,'balistreri2186@mcgill.ca','Lowell Halvorson',0,0,0,0,NULL,NULL,'mcgill',NULL,NULL,0,0),
  (158,'friesen5367@princeton.edu','Tony Lind',0,0,0,0,NULL,NULL,'princeton',NULL,NULL,0,0),
  (159,'aufderhar2058@baylor.edu','Mr. Jamey Schulist',0,0,0,0,NULL,NULL,'baylor',NULL,NULL,0,0),
  (160,'schamberger6008@dartmouth.edu','Lenna Wehner DDS',0,0,0,0,NULL,NULL,'dartmouth',0.1000,NULL,0,0),
  (161,'collins8687@duke.edu','Dalton Lesch',0,0,0,0,NULL,NULL,'duke',NULL,NULL,0,0),
  (162,'batz1276@iu.edu','Sanford Reichel',0,0,0,0,NULL,NULL,'iu',NULL,NULL,0,0),
  (163,'kutch3106@iu.edu','Sam Nicolas',0,0,0,0,NULL,NULL,'iu',0.0500,NULL,0,0),
  (164,'graham7513@iu.edu','Stephanie Botsford',0,0,0,0,NULL,NULL,'iu',NULL,NULL,0,0),
  (165,'williamson8554@iu.edu','Miss Liza Zemlak',0,0,0,0,NULL,NULL,'iu',0.4000,NULL,0,0),
  (166,'sanford8922@iu.edu','Lucious Fahey',0,0,0,0,NULL,NULL,'iu',NULL,NULL,0,0),
  (167,'hilll3296@iu.edu','Ms. Paris Rosenbaum',0,0,0,0,NULL,NULL,'iu',NULL,NULL,0,0),
  (168,'heidenreich1404@iu.edu','Maverick Dickinson',0,0,0,0,NULL,NULL,'iu',NULL,NULL,0,0),
  (169,'mayer9332@iu.edu','Sallie Thompson',0,0,0,0,NULL,NULL,'iu',NULL,NULL,0,0),
  (170,'strosin3302@jhu.edu','Dejuan McKenzie',0,0,0,0,NULL,NULL,'jhu',0.2500,NULL,0,0),
  (171,'ullrich4070@illinois.edu','Salma Daniel',0,0,0,0,NULL,NULL,'illinois',NULL,NULL,0,0),
  (172,'kassulke8429@mcgill.ca','Camryn Murray',0,0,0,0,NULL,NULL,'mcgill',NULL,NULL,0,0),
  (173,'rutherford4642@umich.edu','Luciano O\'Reilly',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (174,'barton2654@virginia.edu','Ms. Zion Reichert',0,0,0,0,NULL,NULL,'virginia',0.0750,NULL,0,0),
  (175,'botsford5713@psu.edu','Vena Ryan',0,0,0,0,NULL,NULL,'psu',0.0800,NULL,0,0),
  (176,'crooks2970@dartmouth.edu','Joaquin McLaughlin',0,0,0,0,NULL,NULL,'dartmouth',0.1000,NULL,0,0),
  (177,'romaguera7460@umich.edu','Amparo Corkery',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (178,'sporer9855@utsa.edu','Christop Connelly',0,0,0,0,NULL,NULL,'utsa',NULL,NULL,0,0),
  (179,'kulas7760@illinois.edu','Alda Cronin',0,0,0,0,NULL,NULL,'illinois',NULL,NULL,0,0),
  (180,'blick1544@northwestern.edu','Kayley Johnston',0,0,0,0,NULL,NULL,'northwestern',NULL,NULL,0,0),
  (181,'zboncak1327@arizona.edu','Raul Emmerich',0,0,0,0,NULL,NULL,'arizona',0.2000,NULL,0,0),
  (182,'funk5250@northwestern.edu','Ethyl Mosciski',0,0,0,0,NULL,NULL,'northwestern',0.0500,NULL,0,0),
  (183,'wiza2213@umd.edu','Rosalia Christiansen',0,0,0,0,NULL,NULL,'umd',0.0500,NULL,0,0),
  (184,'greenholt7729@ucla.edu','Roma Emard',0,0,0,0,NULL,NULL,'ucla',0.0500,NULL,0,0),
  (185,'marvin8048@baylor.edu','Ike Ullrich DVM',0,0,0,0,NULL,NULL,'baylor',0.1700,NULL,0,0),
  (186,'stamm247@umich.edu','Coby Zboncak',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (187,'schulist6418@jhu.edu','Winston Kilback',0,0,0,0,NULL,NULL,'jhu',NULL,NULL,0,0),
  (188,'turcotte9918@ucsf.edu','Maegan Dickens',0,0,0,0,NULL,NULL,'ucsf',0.2000,NULL,0,0),
  (189,'denesik7140@umich.edu','Dariana Batz',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (190,'simonis6300@pitt.edu','Bonnie Wolf',0,0,0,0,NULL,NULL,'pitt',0.0750,NULL,0,0),
  (191,'douglas6363@baylor.edu','Jackie Jast',0,0,0,0,NULL,NULL,'baylor',0.1300,NULL,0,0),
  (192,'hodkiewicz4244@nyu.edu','Aletha Howe',0,0,0,0,NULL,NULL,'nyu',0.1500,NULL,0,0),
  (193,'von3701@arizona.edu','Larue Gaylord',0,0,0,0,NULL,NULL,'arizona',0.0750,NULL,0,0),
  (194,'bruen9044@northwestern.edu','Murphy Rice',0,0,0,0,NULL,NULL,'northwestern',0.0930,NULL,0,0),
  (195,'dickinson7661@unc.edu','Alverta Bartoletti',0,0,0,0,NULL,NULL,'unc',0.1500,NULL,0,0),
  (196,'schroeder4184@unc.edu','Stefanie Pagac',0,0,0,0,NULL,NULL,'unc',0.2000,NULL,0,0),
  (197,'howe1910@ucop.edu','Kaden Langworth',0,0,0,0,NULL,NULL,'ucop',0.0500,NULL,0,0),
  (198,'willms2482@uchicago.edu','Delta Schuster',0,0,0,0,NULL,NULL,'uchicago',0.1500,NULL,0,0),
  (199,'leffler2215@uci.edu','Katlyn Leffler',0,0,0,0,NULL,NULL,'uci',0.2000,NULL,0,0),
  (200,'mcglynn2888@columbia.edu','Dashawn Kshlerin',0,0,0,0,NULL,NULL,'columbia',NULL,NULL,0,0),
  (201,'adams8749@wisc.edu','Roderick Romaguera II',0,0,0,0,NULL,NULL,'wisc',NULL,NULL,0,0),
  (202,'zemlak9768@jhu.edu','Juston Kohler',0,0,0,0,NULL,NULL,'jhu',NULL,NULL,0,0),
  (203,'wisoky4874@umich.edu','Hilda King',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (204,'tremblay188@psu.edu','Allan Harris',0,0,0,0,NULL,NULL,'psu',0.2000,NULL,0,0),
  (205,'reichert234@uci.edu','Torrey Kuhlman',0,0,0,0,NULL,NULL,'uci',0.2000,NULL,0,0),
  (206,'macejkovic4125@psu.edu','Mr. Mariano Feeney',0,0,0,0,NULL,NULL,'psu',0.2000,NULL,0,0),
  (207,'ondricka364@duke.edu','Aurelia Skiles',0,0,0,0,NULL,NULL,'duke',NULL,NULL,0,0),
  (208,'ortiz6101@ucla.edu','Kaley Crist',0,0,0,0,NULL,NULL,'ucla',0.1500,NULL,0,0),
  (209,'hettinger5179@ucsc.edu','Magali Jenkins',0,0,0,0,NULL,NULL,'ucsc',NULL,NULL,0,0),
  (210,'stark7055@cornell.edu','Gennaro Wuckert',0,0,0,0,NULL,NULL,'cornell',0.1500,NULL,0,0),
  (211,'oberbrunner8510@baylor.edu','Houston Cruickshank',0,0,0,0,NULL,NULL,'baylor',0.2100,NULL,0,0),
  (212,'olson5057@umich.edu','Clotilde Rolfson',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (213,'kiehn8070@baylor.edu','Simone Bogan',0,0,0,0,NULL,NULL,'baylor',NULL,NULL,0,0),
  (214,'lockman2438@virginia.edu','Ashlynn Treutel',0,0,0,0,NULL,NULL,'virginia',0.1500,NULL,0,0),
  (215,'berge6768@illinois.edu','Dr. Elsie Dietrich',0,0,0,0,NULL,NULL,'illinois',NULL,NULL,0,0),
  (216,'champlin2575@uh.edu','Horacio Ziemann',0,0,0,0,NULL,NULL,'uh-new',0.0750,NULL,0,0),
  (217,'leannon2351@psu.edu','Claude Bergnaum',0,0,0,0,NULL,NULL,'psu',0.0450,NULL,0,0),
  (218,'kreiger5653@umd.edu','Cornelius Price',0,0,0,0,NULL,NULL,'umd',0.0500,NULL,0,0),
  (219,'koepp3503@duke.edu','Ernie Gibson',0,0,0,0,NULL,NULL,'duke',NULL,NULL,0,0),
  (220,'stroman6272@umich.edu','Mrs. Thalia Anderson',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (221,'schaden1488@northwestern.edu','Stevie King',0,0,0,0,NULL,NULL,'northwestern',0.0223,NULL,0,0),
  (222,'hartmann4357@illinois.edu','Jammie Gislason I',0,0,0,0,NULL,NULL,'illinois',NULL,NULL,0,0),
  (223,'graham2992@ucla.edu','Francis Leuschke',0,0,0,0,NULL,NULL,'ucla',0.0500,NULL,0,0),
  (224,'terry3765@lafayette.edu','Velda Yost',0,0,0,0,NULL,NULL,'lafayette',0.1000,NULL,0,0),
  (225,'king4517@umich.edu','Lourdes Effertz',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (226,'harvey1331@umich.edu','Jameson Littel III',0,0,0,0,NULL,NULL,'umich',NULL,NULL,0,0),
  (227,'zieme6475@txstate.edu','Dr. Pearl Conroy',0,0,0,0,NULL,NULL,'txstate',0.1500,NULL,0,0),
  (228,'harber383@osu.edu','Madaline King I',0,0,0,0,NULL,NULL,'osu',0.0750,NULL,0,0),
  (229,'strosin2748@mcmaster.ca','Philip Hoeger',0,0,0,0,NULL,NULL,'mcmaster',NULL,NULL,0,0),
  (230,'leffler4243@ufl.edu','Taylor Reinger',0,0,0,0,NULL,NULL,'ufl',0.1500,NULL,0,0);
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;
