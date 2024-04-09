CREATE DATABASE IF NOT EXISTS crms;
USE crms;

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `T_BOOK_DM`
--

DROP TABLE IF EXISTS `T_BOOK_DM`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `T_BOOK_DM` (
  `id` int(11) NOT NULL,
  `hld_id` varchar(20) DEFAULT NULL,
  `Hid_o` varchar(20) DEFAULT NULL,
  `bib_bid` varchar(20) DEFAULT NULL,
  `bookid` varchar(28) DEFAULT NULL,
  `bookid_o` varchar(24) DEFAULT NULL,
  `wy` varchar(2) DEFAULT NULL,
  `cln` varchar(100) DEFAULT NULL,
  `isbn` varchar(28) DEFAULT NULL,
  `ndl_no` varchar(16) DEFAULT NULL,
  `ndc` varchar(28) DEFAULT NULL,
  `245a` text,
  `245ak` text,
  `245b` text,
  `245bk` text,
  `245vol` text,
  `245c` text,
  `245ck` text,
  `246a` text,
  `250a` text,
  `260a` text,
  `260b` text,
  `260c` text,
  `260c_` text,
  `300a` text,
  `300b` text,
  `300c` text,
  `440a_1` text,
  `440ak_1` text,
  `440vol_1` text,
  `440c_1` text,
  `440ck_1` text,
  `440a_2` text,
  `440ak_2` text,
  `440vol_2` text,
  `440c_2` text,
  `440ck_2` text,
  `505` text,
  `700a_1` text,
  `700ak_1` text,
  `700a_2` text,
  `700ak_2` text,
  `note` text,
  `cls` varchar(20) DEFAULT NULL,
  `jbisc` text,
  `tagdata` text,
  `rep` varchar(4) DEFAULT NULL,
  `label` varchar(20) DEFAULT NULL,
  `label_hosoi` varchar(20) DEFAULT NULL,
  `copy` varchar(4) DEFAULT NULL,
  `end` varchar(4) DEFAULT NULL,
  `sort` varchar(40) DEFAULT NULL,
  `staff` varchar(100) DEFAULT NULL,
  `kindig_stat` varchar(100) DEFAULT NULL,
  `kindig_bookno` varchar(16) DEFAULT NULL,
  `honbun_chek` varchar(4) DEFAULT NULL,
  `botuneu_chousa` varchar(4) DEFAULT NULL,
  `statu` varchar(100) DEFAULT NULL,
  `hikoukai_` varchar(100) DEFAULT NULL,
  `smd` varchar(100) DEFAULT NULL,
  `mem` text,
  `dup` varchar(2) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `authorities`
--

DROP TABLE IF EXISTS `authorities`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `authorities` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(32) DEFAULT NULL,
  `url` mediumtext,
  `accesskey` char(1) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=67 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `projects`
--

DROP TABLE IF EXISTS `projects`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `projects` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `queue_size` int(11) NOT NULL DEFAULT '0',
  `autoinherit` tinyint(4) NOT NULL DEFAULT '0',
  `group_volumes` tinyint(4) NOT NULL DEFAULT '0',
  `single_review` tinyint(4) NOT NULL DEFAULT '0',
  `primary_authority` int(11) DEFAULT NULL,
  `secondary_authority` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`),
  KEY `fk_auth1` (`primary_authority`),
  KEY `fk_auth2` (`secondary_authority`),
  CONSTRAINT `projects_ibfk_1` FOREIGN KEY (`primary_authority`) REFERENCES `authorities` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `projects_ibfk_2` FOREIGN KEY (`secondary_authority`) REFERENCES `authorities` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=23 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `reviewdata`
--

DROP TABLE IF EXISTS `reviewdata`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `reviewdata` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `data` text NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=127957 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `attributes`
--

DROP TABLE IF EXISTS `attributes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `attributes` (
  `id` tinyint(3) unsigned NOT NULL AUTO_INCREMENT,
  `type` enum('access','copyright') NOT NULL DEFAULT 'access',
  `name` varchar(16) NOT NULL DEFAULT '',
  `dscr` text NOT NULL,
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=28 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `bibdata`
--

DROP TABLE IF EXISTS `bibdata`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `bibdata` (
  `id` varchar(32) NOT NULL DEFAULT '',
  `title` text,
  `author` text,
  `pub_date` date DEFAULT NULL,
  `country` text,
  `sysid` varchar(32) DEFAULT NULL,
  `display_date` varchar(16) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `author_idx` (`author`(255)),
  KEY `title_idx` (`title`(255)),
  KEY `sysid_idx` (`sysid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `candidates`
--

DROP TABLE IF EXISTS `candidates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `candidates` (
  `id` varchar(32) NOT NULL DEFAULT '',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `project` int(11) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`),
  KEY `fk_project` (`project`),
  CONSTRAINT `candidates_ibfk_2` FOREIGN KEY (`project`) REFERENCES `projects` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `candidatesrecord`
--

DROP TABLE IF EXISTS `candidatesrecord`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `candidatesrecord` (
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `addedamount` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `catalog`
--

DROP TABLE IF EXISTS `catalog`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `catalog` (
  `id` varchar(32) NOT NULL,
  `leader` varchar(24) NOT NULL,
  `f_008` varchar(40) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `categories`
--

DROP TABLE IF EXISTS `categories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `categories` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(32) NOT NULL,
  `restricted` varchar(32) DEFAULT NULL,
  `interface` tinyint(1) NOT NULL DEFAULT '1',
  `need_note` tinyint(1) NOT NULL DEFAULT '1',
  `need_und` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=70 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `corrections`
--

DROP TABLE IF EXISTS `corrections`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `corrections` (
  `id` varchar(32) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `locked` varchar(64) DEFAULT NULL,
  `user` varchar(64) DEFAULT NULL,
  `status` varchar(32) DEFAULT NULL,
  `ticket` varchar(32) DEFAULT NULL,
  `note` text,
  `exported` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dbo_T_BOOK`
--

DROP TABLE IF EXISTS `dbo_T_BOOK`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dbo_T_BOOK` (
  `id` int(11) NOT NULL,
  `hld_id` varchar(20) DEFAULT NULL,
  `Hid_o` varchar(20) DEFAULT NULL,
  `bib_bid` varchar(20) DEFAULT NULL,
  `bookid` varchar(28) DEFAULT NULL,
  `bookid_o` varchar(24) DEFAULT NULL,
  `wy` varchar(2) DEFAULT NULL,
  `cln` varchar(100) DEFAULT NULL,
  `isbn` varchar(28) DEFAULT NULL,
  `ndl_no` varchar(16) DEFAULT NULL,
  `ndc` varchar(28) DEFAULT NULL,
  `245a` text,
  `245ak` text,
  `245b` text,
  `245bk` text,
  `245vol` text,
  `245c` text,
  `245ck` text,
  `246a` text,
  `250a` text,
  `260a` text,
  `260b` text,
  `260c` text,
  `260c_` text,
  `300a` text,
  `300b` text,
  `300c` text,
  `440a_1` text,
  `440ak_1` text,
  `440vol_1` text,
  `440c_1` text,
  `440ck_1` text,
  `440a_2` text,
  `440ak_2` text,
  `440vol_2` text,
  `440c_2` text,
  `440ck_2` text,
  `505` text,
  `700a_1` text,
  `700ak_1` text,
  `700a_2` text,
  `700ak_2` text,
  `note` text,
  `cls` varchar(20) DEFAULT NULL,
  `jbisc` text,
  `tagdata` text,
  `rep` varchar(4) DEFAULT NULL,
  `label` varchar(20) DEFAULT NULL,
  `label_hosoi` varchar(20) DEFAULT NULL,
  `copy` varchar(4) DEFAULT NULL,
  `end` varchar(4) DEFAULT NULL,
  `sort` varchar(40) DEFAULT NULL,
  `staff` varchar(100) DEFAULT NULL,
  `kindig_stat` varchar(100) DEFAULT NULL,
  `kindig_bookno` varchar(16) DEFAULT NULL,
  `honbun_chek` varchar(4) DEFAULT NULL,
  `botuneu_chousa` varchar(4) DEFAULT NULL,
  `statu` varchar(100) DEFAULT NULL,
  `hikoukai_` varchar(100) DEFAULT NULL,
  `smd` varchar(100) DEFAULT NULL,
  `mem` text,
  `dup` varchar(2) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `hld_id` (`hld_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dbo_T_aid`
--

DROP TABLE IF EXISTS `dbo_T_aid`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dbo_T_aid` (
  `id` int(11) NOT NULL,
  `aut_id_f` varchar(20) DEFAULT NULL,
  `aut_id_t` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dbo_T_aid_set_B`
--

DROP TABLE IF EXISTS `dbo_T_aid_set_B`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dbo_T_aid_set_B` (
  `id` int(11) DEFAULT NULL,
  `cd` varchar(2) DEFAULT NULL,
  `aid` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dbo_T_aid_set_E`
--

DROP TABLE IF EXISTS `dbo_T_aid_set_E`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dbo_T_aid_set_E` (
  `id` int(11) DEFAULT NULL,
  `cd` varchar(2) DEFAULT NULL,
  `aid` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dbo_T_aid_set_F`
--

DROP TABLE IF EXISTS `dbo_T_aid_set_F`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dbo_T_aid_set_F` (
  `id` int(11) DEFAULT NULL,
  `cd` varchar(2) DEFAULT NULL,
  `aid` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dbo_T_aid_set_H`
--

DROP TABLE IF EXISTS `dbo_T_aid_set_H`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dbo_T_aid_set_H` (
  `id` int(11) DEFAULT NULL,
  `cd` varchar(2) DEFAULT NULL,
  `aid` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dbo_T_aid_set_J`
--

DROP TABLE IF EXISTS `dbo_T_aid_set_J`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dbo_T_aid_set_J` (
  `id` int(11) DEFAULT NULL,
  `cd` varchar(2) DEFAULT NULL,
  `aid` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dbo_T_aid_set_M`
--

DROP TABLE IF EXISTS `dbo_T_aid_set_M`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dbo_T_aid_set_M` (
  `id` int(11) DEFAULT NULL,
  `cd` varchar(2) DEFAULT NULL,
  `aid` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dbo_T_aid_set_P`
--

DROP TABLE IF EXISTS `dbo_T_aid_set_P`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dbo_T_aid_set_P` (
  `id` int(11) DEFAULT NULL,
  `cd` varchar(2) DEFAULT NULL,
  `aid` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dbo_T_aut`
--

DROP TABLE IF EXISTS `dbo_T_aut`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dbo_T_aut` (
  `id` int(11) NOT NULL,
  `aut_id` varchar(16) DEFAULT NULL,
  `aut_nam` varchar(510) DEFAULT NULL,
  `aut_nam_y` varchar(510) DEFAULT NULL,
  `aut_year` varchar(510) DEFAULT NULL,
  `aut_dth_y` varchar(510) DEFAULT NULL,
  `aut_nayose` varchar(510) DEFAULT NULL,
  `aut_nayose2` varchar(510) DEFAULT NULL,
  `aut_tags` text,
  `aut_bid` varchar(510) DEFAULT NULL,
  `alias` varchar(510) DEFAULT NULL,
  `botsunen_` varchar(2) DEFAULT NULL,
  `kindegi_stat` varchar(510) DEFAULT NULL,
  `tool1` varchar(510) DEFAULT NULL,
  `tool2` varchar(510) DEFAULT NULL,
  `stat` varchar(510) DEFAULT NULL,
  `resu` varchar(510) DEFAULT NULL,
  `memo` varchar(510) DEFAULT NULL,
  `staff` varchar(100) DEFAULT NULL,
  `temp_no` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `aut_id` (`aut_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dbo_T_aut_hld`
--

DROP TABLE IF EXISTS `dbo_T_aut_hld`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dbo_T_aut_hld` (
  `id` int(11) NOT NULL,
  `aut_id` varchar(16) DEFAULT NULL,
  `hld_id` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `hld_id` (`hld_id`),
  KEY `aut_id` (`aut_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `dbo_T_code`
--

DROP TABLE IF EXISTS `dbo_T_code`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dbo_T_code` (
  `id` int(11) DEFAULT NULL,
  `c_id` int(11) DEFAULT NULL,
  `code` int(11) DEFAULT NULL,
  `decode` varchar(510) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `exportdata`
--

DROP TABLE IF EXISTS `exportdata`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `exportdata` (
  `id` varchar(32) DEFAULT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `attr` varchar(32) DEFAULT NULL,
  `reason` varchar(32) DEFAULT NULL,
  `status` int(1) DEFAULT '0',
  `priority` decimal(4,2) NOT NULL DEFAULT '0.00',
  `src` varchar(32) DEFAULT NULL,
  `gid` bigint(20) NOT NULL AUTO_INCREMENT,
  `exported` tinyint(1) NOT NULL DEFAULT '1',
  `added_by` varchar(64) DEFAULT NULL,
  `ticket` varchar(32) DEFAULT NULL,
  `project` int(11) NOT NULL DEFAULT '1',
  PRIMARY KEY (`gid`),
  KEY `time_idx` (`time`),
  KEY `id_idx` (`id`),
  KEY `status_idx` (`status`),
  KEY `priority_idx` (`priority`),
  KEY `fk_project` (`project`),
  CONSTRAINT `exportdata_ibfk_1` FOREIGN KEY (`project`) REFERENCES `projects` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=1737265 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `exportrecord`
--

DROP TABLE IF EXISTS `exportrecord`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `exportrecord` (
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `itemcount` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `exportstats`
--

DROP TABLE IF EXISTS `exportstats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `exportstats` (
  `date` date NOT NULL,
  `attr` varchar(32) NOT NULL,
  `reason` varchar(32) NOT NULL,
  `count` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`date`,`attr`,`reason`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `historicalreviews`
--

DROP TABLE IF EXISTS `historicalreviews`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `historicalreviews` (
  `id` varchar(32) NOT NULL DEFAULT '',
  `time` varchar(100) NOT NULL DEFAULT '',
  `user` varchar(64) NOT NULL,
  `attr` tinyint(4) NOT NULL DEFAULT '0',
  `reason` tinyint(4) NOT NULL DEFAULT '0',
  `note` text,
  `category` varchar(32) DEFAULT NULL,
  `expert` int(1) DEFAULT NULL,
  `duration` varchar(10) DEFAULT '00:00:00',
  `legacy` int(11) DEFAULT '0',
  `swiss` tinyint(1) DEFAULT NULL,
  `validated` tinyint(4) NOT NULL DEFAULT '1',
  `gid` bigint(20) DEFAULT NULL,
  `data` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`id`,`time`,`user`),
  KEY `attr_idx` (`attr`),
  KEY `reason_idx` (`reason`),
  KEY `id_idx` (`id`),
  KEY `time_idx` (`time`),
  KEY `user_idx` (`user`),
  KEY `gid_idx` (`gid`),
  KEY `fk_data` (`data`),
  CONSTRAINT `historicalreviews_ibfk_1` FOREIGN KEY (`data`) REFERENCES `reviewdata` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `inherit`
--

DROP TABLE IF EXISTS `inherit`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `inherit` (
  `id` varchar(32) NOT NULL,
  `attr` tinyint(4) NOT NULL,
  `reason` tinyint(4) NOT NULL,
  `gid` bigint(20) NOT NULL,
  `del` tinyint(1) DEFAULT '0',
  `status` tinyint(4) DEFAULT NULL,
  `src` varchar(32) NOT NULL DEFAULT 'export',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `inserts`
--

DROP TABLE IF EXISTS `inserts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `inserts` (
  `id` varchar(32) NOT NULL,
  `iid` int(11) NOT NULL DEFAULT '0',
  `user` varchar(64) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `renewed` tinyint(4) NOT NULL,
  `renNum` varchar(12) DEFAULT NULL,
  `renDateY` int(11) DEFAULT NULL,
  `renDateM` int(11) DEFAULT NULL,
  `renDateD` int(11) DEFAULT NULL,
  `page` int(11) NOT NULL DEFAULT '0',
  `author` mediumtext,
  `title` mediumtext,
  `pub_date` int(11) DEFAULT NULL,
  `pub_history` mediumtext,
  `type` varchar(32) DEFAULT NULL,
  `timer` time NOT NULL DEFAULT '00:00:00',
  `source` varchar(32) NOT NULL,
  `reason` varchar(32) NOT NULL,
  `hold` timestamp NULL DEFAULT NULL,
  `estimate` int(11) DEFAULT NULL,
  `insufficient` int(11) DEFAULT NULL,
  `pd` tinyint(1) DEFAULT NULL,
  `restored` tinyint(1) NOT NULL DEFAULT '0',
  `override` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`,`iid`,`user`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `insertsqueue`
--

DROP TABLE IF EXISTS `insertsqueue`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `insertsqueue` (
  `id` varchar(32) NOT NULL,
  `locked` varchar(64) DEFAULT NULL,
  `status` tinyint(4) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `insertstotals`
--

DROP TABLE IF EXISTS `insertstotals`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `insertstotals` (
  `id` varchar(32) NOT NULL,
  `user` varchar(64) NOT NULL,
  `type` varchar(32) NOT NULL,
  `total` int(11) NOT NULL DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `institutions`
--

DROP TABLE IF EXISTS `institutions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `institutions` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` longtext NOT NULL,
  `shortname` longtext NOT NULL,
  `suffix` varchar(31) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `mail`
--

DROP TABLE IF EXISTS `mail`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mail` (
  `user` varchar(64) NOT NULL,
  `created` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `sent` timestamp NULL DEFAULT NULL,
  `id` varchar(32) DEFAULT NULL,
  `text` text NOT NULL,
  `uuid` varchar(36) NOT NULL,
  `mailto` text,
  `wait` tinyint(4) NOT NULL DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `menuitems`
--

DROP TABLE IF EXISTS `menuitems`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `menuitems` (
  `menu` int(11) NOT NULL,
  `name` text NOT NULL,
  `href` text,
  `page` varchar(32) DEFAULT NULL,
  `restricted` varchar(32) DEFAULT NULL,
  `target` varchar(32) DEFAULT NULL,
  `n` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `menus`
--

DROP TABLE IF EXISTS `menus`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `menus` (
  `id` int(11) NOT NULL,
  `name` varchar(32) NOT NULL,
  `class` varchar(32) DEFAULT NULL,
  `restricted` varchar(32) DEFAULT NULL,
  `n` int(11) NOT NULL,
  `docs` tinyint(1) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `note`
--

DROP TABLE IF EXISTS `note`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `note` (
  `note` mediumtext,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `orphan`
--

DROP TABLE IF EXISTS `orphan`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `orphan` (
  `id` varchar(32) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `processstatus`
--

DROP TABLE IF EXISTS `processstatus`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `processstatus` (
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `users` (
  `id` varchar(64) NOT NULL,
  `kerberos` varchar(64) DEFAULT NULL,
  `name` mediumtext NOT NULL,
  `reviewer` tinyint(1) NOT NULL DEFAULT '1',
  `advanced` tinyint(1) NOT NULL DEFAULT '0',
  `expert` tinyint(1) NOT NULL DEFAULT '0',
  `admin` tinyint(1) NOT NULL DEFAULT '0',
  `alias` varchar(64) DEFAULT NULL,
  `note` text,
  `institution` int(11) NOT NULL DEFAULT '0',
  `commitment` decimal(4,4) DEFAULT NULL,
  `project` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_institution` (`institution`),
  KEY `fk_project` (`project`),
  CONSTRAINT `fk_institution` FOREIGN KEY (`institution`) REFERENCES `institutions` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `users_ibfk_2` FOREIGN KEY (`project`) REFERENCES `projects` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `projectauthorities`
--

DROP TABLE IF EXISTS `projectauthorities`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `projectauthorities` (
  `project` int(11) DEFAULT NULL,
  `authority` int(11) NOT NULL,
  KEY `fk_proj` (`project`),
  KEY `fk_cat` (`authority`),
  CONSTRAINT `projectauthorities_ibfk_1` FOREIGN KEY (`project`) REFERENCES `projects` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `projectauthorities_ibfk_2` FOREIGN KEY (`authority`) REFERENCES `authorities` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `projectcategories`
--

DROP TABLE IF EXISTS `projectcategories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `projectcategories` (
  `project` int(11) DEFAULT NULL,
  `category` int(11) NOT NULL,
  KEY `fk_proj` (`project`),
  KEY `fk_cat` (`category`),
  CONSTRAINT `projectcategories_ibfk_1` FOREIGN KEY (`project`) REFERENCES `projects` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `projectcategories_ibfk_2` FOREIGN KEY (`category`) REFERENCES `categories` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `projectrights`
--

DROP TABLE IF EXISTS `projectrights`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `projectrights` (
  `project` int(11) NOT NULL DEFAULT '1',
  `rights` int(11) NOT NULL,
  KEY `fk_project` (`project`),
  CONSTRAINT `projectrights_ibfk_2` FOREIGN KEY (`project`) REFERENCES `projects` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `projectusers`
--

DROP TABLE IF EXISTS `projectusers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `projectusers` (
  `project` int(11) NOT NULL,
  `user` varchar(64) NOT NULL,
  KEY `fk_proj` (`project`),
  KEY `fk_user` (`user`),
  CONSTRAINT `projectusers_ibfk_1` FOREIGN KEY (`project`) REFERENCES `projects` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `projectusers_ibfk_2` FOREIGN KEY (`user`) REFERENCES `users` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `publishers`
--

DROP TABLE IF EXISTS `publishers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `publishers` (
  `nff` varchar(2) NOT NULL,
  `name` text NOT NULL,
  `citystate` text,
  `email` text,
  `phone` text,
  `postal` text,
  `added` date NOT NULL,
  `notes1` text,
  `notes2` text,
  `reviewed` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `queue`
--

DROP TABLE IF EXISTS `queue`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `queue` (
  `id` varchar(32) NOT NULL DEFAULT '',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `status` int(1) DEFAULT '0',
  `pending_status` int(1) NOT NULL DEFAULT '0',
  `locked` varchar(64) DEFAULT NULL,
  `priority` decimal(4,2) NOT NULL DEFAULT '0.00',
  `source` varchar(32) NOT NULL DEFAULT 'candidates',
  `added_by` varchar(64) DEFAULT NULL,
  `ticket` varchar(32) DEFAULT NULL,
  `project` int(11) NOT NULL DEFAULT '1',
  `unavailable` tinyint(4) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `status_idx` (`status`),
  KEY `locked_idx` (`locked`),
  KEY `priority_idx` (`priority`),
  KEY `fk_project` (`project`),
  CONSTRAINT `queue_ibfk_1` FOREIGN KEY (`project`) REFERENCES `projects` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `queuerecord`
--

DROP TABLE IF EXISTS `queuerecord`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `queuerecord` (
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `itemcount` int(11) DEFAULT NULL,
  `source` varchar(32) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `reasons`
--

DROP TABLE IF EXISTS `reasons`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `reasons` (
  `id` tinyint(3) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(16) NOT NULL DEFAULT '',
  `dscr` text NOT NULL,
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `renewals`
--

DROP TABLE IF EXISTS `renewals`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `renewals` (
  `renewal_id` varchar(32) NOT NULL,
  `renewal_date` date NOT NULL,
  `registration_id` varchar(32) NOT NULL,
  `registration_date` date NOT NULL,
  `in_renewals` tinyint(4) NOT NULL DEFAULT '0',
  `author` text,
  `title` text,
  `cce_vol` text,
  `sysid` varchar(32) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `reviews`
--

DROP TABLE IF EXISTS `reviews`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `reviews` (
  `id` varchar(32) NOT NULL DEFAULT '',
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `user` varchar(64) NOT NULL,
  `attr` tinyint(4) NOT NULL DEFAULT '0',
  `reason` tinyint(4) NOT NULL DEFAULT '0',
  `note` text,
  `category` varchar(32) DEFAULT NULL,
  `expert` int(1) DEFAULT NULL,
  `duration` varchar(10) DEFAULT '00:00:00',
  `legacy` int(11) DEFAULT '0',
  `swiss` tinyint(1) DEFAULT NULL,
  `hold` tinyint(4) NOT NULL DEFAULT '0',
  `data` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`id`,`user`),
  KEY `attr_idx` (`attr`),
  KEY `reason_idx` (`reason`),
  KEY `fk_data` (`data`),
  CONSTRAINT `reviews_ibfk_1` FOREIGN KEY (`data`) REFERENCES `reviewdata` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `rights`
--

DROP TABLE IF EXISTS `rights`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `rights` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `attr` tinyint(4) NOT NULL,
  `reason` tinyint(4) NOT NULL,
  `description` text,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=26 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `stanford`
--

DROP TABLE IF EXISTS `stanford`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `stanford` (
  `ID` mediumtext NOT NULL,
  `DREG` varchar(10) DEFAULT NULL,
  PRIMARY KEY (`ID`(30))
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `systemstatus`
--

DROP TABLE IF EXISTS `systemstatus`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `systemstatus` (
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `status` varchar(32) DEFAULT NULL,
  `message` text
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `systemvars`
--

DROP TABLE IF EXISTS `systemvars`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `systemvars` (
  `name` varchar(32) NOT NULL DEFAULT '',
  `value` text,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `unavailable`
--

DROP TABLE IF EXISTS `unavailable`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `unavailable` (
  `id` varchar(32) NOT NULL,
  `src` varchar(32) NOT NULL DEFAULT 'export'
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `und`
--

DROP TABLE IF EXISTS `und`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `und` (
  `id` varchar(32) NOT NULL,
  `src` varchar(32) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `userstats`
--

DROP TABLE IF EXISTS `userstats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `userstats` (
  `user` varchar(64) NOT NULL,
  `month` varchar(2) DEFAULT NULL,
  `year` varchar(4) DEFAULT NULL,
  `monthyear` varchar(7) NOT NULL DEFAULT '',
  `project` int(11) NOT NULL DEFAULT '1',
  `total_reviews` int(11) DEFAULT NULL,
  `total_pd` int(11) NOT NULL,
  `total_ic` int(11) NOT NULL,
  `total_und` int(11) NOT NULL,
  `total_time` int(11) DEFAULT NULL,
  `time_per_review` double DEFAULT NULL,
  `reviews_per_hour` double DEFAULT NULL,
  `total_outliers` int(11) DEFAULT NULL,
  `total_correct` int(11) DEFAULT NULL,
  `total_incorrect` int(11) DEFAULT NULL,
  `total_neutral` int(11) DEFAULT NULL,
  PRIMARY KEY (`user`,`monthyear`,`project`),
  KEY `fk_project` (`project`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_pages`
--

DROP TABLE IF EXISTS `user_pages`;
CREATE TABLE `user_pages` (
  `user` varchar(64) NOT NULL,
  `page` varchar(32) NOT NULL,
  KEY `user_pages_ibfk_user` (`user`),
  CONSTRAINT `user_pages_ibfk_user` FOREIGN KEY (`user`) REFERENCES `users` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `viaf`
--

DROP TABLE IF EXISTS `viaf`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `viaf` (
  `author` text NOT NULL,
  `viaf_author` text NOT NULL,
  `birth_year` varchar(4) DEFAULT NULL,
  `death_year` varchar(4) DEFAULT NULL,
  `country` text,
  `viafID` varchar(31) NOT NULL,
  `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `licensing`
--

DROP TABLE IF EXISTS `licensing`;
CREATE TABLE licensing (
  `id` BIGINT(20) AUTO_INCREMENT PRIMARY KEY NOT NULL,
  `htid` VARCHAR(32) NOT NULL,
  `time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `user` VARCHAR(64) NOT NULL,
  `attr` TINYINT(3) UNSIGNED NOT NULL,
  `reason` TINYINT(3) UNSIGNED NOT NULL,
  `ticket` VARCHAR(32) NOT NULL,
  `rights_holder` TEXT,
  `rights_file` TEXT NULL DEFAULT NULL,
  CONSTRAINT `manual_permissions_ibfk_user` FOREIGN KEY (`user`) REFERENCES `users` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `manual_permissions_ibfk_attr` FOREIGN KEY (`attr`) REFERENCES `attributes` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `manual_permissions_ibfk_reason` FOREIGN KEY (`reason`) REFERENCES `reasons` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


--
-- Table structure for table `cron`
--

DROP TABLE IF EXISTS `cron`;
CREATE TABLE cron (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY NOT NULL,
  `script` VARCHAR(64) UNIQUE NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `cron_recipients`
--

DROP TABLE IF EXISTS `cron_recipients`;
CREATE TABLE cron_recipients (
  `cron_id` BIGINT NOT NULL,
  `email` VARCHAR(64) NOT NULL,
  CONSTRAINT `cron_recipients_fk_cron_id` FOREIGN KEY (`cron_id`) REFERENCES `cron` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

GRANT ALL PRIVILEGES ON `crms`.* TO 'crms'@'%' IDENTIFIED BY 'crms';
