-- MySQL dump 10.9
--
-- Host: localhost    Database: crms
-- ------------------------------------------------------
-- Server version	4.1.10a-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;

--
-- Table structure for table `bibdata`
--

DROP TABLE IF EXISTS `bibdata`;
CREATE TABLE `bibdata` (
  `id` varchar(32) NOT NULL default '',
  `title` text,
  `author` text,
  `pub_date` date default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `bibdata`
--


/*!40000 ALTER TABLE `bibdata` DISABLE KEYS */;
LOCK TABLES `bibdata` WRITE;
INSERT INTO `bibdata` VALUES ('mdp.39015010885039','Atomic energy :','United Nations.Terminology Section.','1958-01-01'),('mdp.39015023082301','Communicating information and ideas about the United Nations to the American people.','Cory, Robert H.','1955-01-01'),('mdp.39015024910328','Comparison of steel-making processes.','United Nations.Economic Commission for Europe.','1962-01-01'),('mdp.39015024912613','Proceedings.','Regional Seminar on Energy Resources and Electric Power Development(1961 :Bangkok, Thailand)United Nations.Economic Commission for Asia and the Far East.','1962-01-01'),('mdp.39015064503116','Höher als die kirche,','Hillern, Wilhelmine von,1836-1916.Nippert, Eleanore Cathrine,ed.','1928-01-01'),('mdp.39015064504643','The importance of the printing industry;','Gustafson, David.','1931-01-01'),('mdp.39015064521340','Asymptotische Gesetze der Wahrscheinlichkeitsrechnung.','Khinchin, Aleksandr I︠A︡kovlevich,1894-1959.','1948-01-01'),('mdp.39015064535944','A handbook of flags.','Kannik, Preben.','1958-01-01'),('mdp.39015064537056','A great lord /','Frischauer, Paul,1898-1977.Blewitt, Phyllis,tr.Blewitt, Trevor Eaton,1900-joint tr.','1937-01-01'),('mdp.39015064540944','Die Idee der Riemannschen Fläche.','Weyl, Hermann,1885-1955.','1947-01-01'),('mdp.39015064543161','Herr Volcnant von Erlach, Minnesinger;','Kephart, Calvin,1883-','1949-01-01'),('mdp.39015065132402','A nail merchant at nightfall,','Waltari, Mika,1908-1979.','1954-01-01'),('mdp.39015065134051','The awakening of Motek :','Ronṭsh, Yitsḥaḳ Elḥanan,1899-','1953-01-01'),('mdp.39015065246095','Durni dity :','Kruk-Mazepynet︠s︡ʹ, I︠U︡. R.','1955-01-01'),('mdp.39015065274550','When the gods are silent;','Soloviev, Mikhail,1908-','1952-01-01'),('mdp.39015065294897','1943-1958 :','Ivanov, Georgiĭ,1894-1958.','1958-01-01'),('mdp.39015065311360','Time walked.','Panova, Vera Fedorovna,1905-1973.','1959-01-01'),('mdp.39015065322946','The bluebottle','Tarsis, Valeriĭ,1908-','1963-01-01'),('mdp.39015065378260','The little clay cart;','Śūdraka.Ryder, Arthur William,1877-1938,tr.Morgan, Agnes,ed.','1934-01-01'),('mdp.39015065432463','Mark Twain\'s works.','Twain, Mark,1835-1910.','1933-01-01'),('mdp.39015065432505','Mark Twain\'s works.','Twain, Mark,1835-1910.','1933-01-01'),('mdp.39015065432711','Basic information on the aged.','Cohen, Wilbur J.(Wilbur Joseph),1913-1987.','1959-01-01'),('mdp.39015065452750','Son of Talleyrand;','Bernardy, Françoise de.','1957-01-01'),('mdp.39015065498217','Taras Bulba,','Gogolʹ, Nikolaĭ Vasilʹevich,1809-1852.Hapgood, Isabel Florence,1850-1928.','1931-01-01'),('mdp.39015065510052','Science and the course of history /','Jordon, Pascual,1902-','1955-01-01'),('mdp.39015065510235','Science advances.','Haldane, J. B. S.(John Burdon Sanderson),1892-1964.','1948-01-01'),('mdp.39015065510284','Matteo Ricci\'s scientific contribution to China','Bernard, Henri.','1960-01-01'),('mdp.39015065511563','Our sun /','Menzel, Donald H.(Donald Howard),1901-1976.','1949-01-01'),('mdp.39015065512181','Linear feedback analysis.','Thomason, James Gordon.','1955-01-01'),('mdp.39015065512322','Fundamentals of electroacoustics /','Fischer, Friedrich Alexander.','1955-01-01'),('mdp.39015065512413','German-English dictionary for electronics engineers and physicists with a patent-practice vocabulary /','Regen, Bernard R.Regen, Richard R.','1946-01-01'),('mdp.39015065516968','Urban land appraisal :','International Association of Assessing Officers.Welch, Ronald B.','1940-01-01'),('mdp.39015065528336','The double agent;','Blackmur, R. P.(Richard P.),1904-1965.','1962-01-01'),('mdp.39015065528617','In defense of reason.','Winters, Yvor,1900-1968.','1959-01-01'),('mdp.39015065530274','Every other bed.','Gorman, Mike,1913-','1956-01-01'),('mdp.39015065530282','Sociology and the field of mental health;','Clausen, John A.American Sociological Association.','1956-01-01'),('mdp.39015065530290','Psychiatric aide education /','Hall, Bernard Horace,1919-','1952-01-01'),('mdp.39015065531579','First steps toward a modern constitution.','New York (State).Temporary Commission on the Revision and Simplification of the Constitution.','1959-01-01'),('mdp.39015065644430','Soviet science of interstellar space.','Pikelʹner, S. B.(Solomon Borisovich)','1963-01-01'),('mdp.39015065646955','The Volga falls to the Caspian sea;','Pilʹni︠a︡k, Boris,1894-1937.Malamuth, Charles,tr.','1931-01-01'),('mdp.39015065654256','Radioactive substances;','Curie, Marie,1867-1934.','1961-01-01'),('mdp.39015065655576','Principles and practice of chromatography,','Zechmeister, L.(László),1889-1972.Cholnoky, L.(László),1899-joint author.Bacharach, A. L.(Alfred Louis),1891-1966.tr.Robinson, Frank Arnold,joint tr.','1941-01-01'),('mdp.39015065660857','The resistance of the air to stone-dropping meteors.','Nelson, Harry E.','1953-01-01'),('mdp.39015065661939','Scientific and technical aspects of the control of atomic energy;','United Nations.Atomic Energy Commission.Scientific and Technical Committee.','1946-01-01'),('mdp.39015065668397','Causes of mental disorders:','Round Table en Causes of Mental Disorders: A Review of Epidemiological Knowledge, Arden House,1959.Milbank Memorial Fund.','1961-01-01'),('mdp.39015065671086','National politics and Federal aid to education','Munger, Frank J.Fenno, Richard F.,1926-','1962-01-01'),('mdp.39015065676309','Proceedings of the Institute of Petroleum Hydrocarbon Research Group Conference on Molecular Spectroscopy.','Conference on Molecular Spectroscopy,London,1958.Thornton, Edwined.Thompson, Harold Warris,1908-Institute of Petroleum (Great Britain)Hydrocarbon Research Group.','1959-01-01'),('mdp.39015065683149','Economic measures in favour of the family;','United Nations.Dept. of Social Affairs.','1952-01-01'),('mdp.39015065683610','Isaac Newton, 1642-1727,','Sullivan, J. W. N.(John William Navin),1886-1937.Singer, Charles Joseph,1876-1960.','1938-01-01'),('mdp.39015065692769','Reports of the Governor\'s citizens\' committees.','Mason, Bruce Bonner.ed.Jackson, Penrose B.,joint ed.','1956-01-01'),('mdp.39015065692850','The bird:','Hess, Gertrud,1910-','1951-01-01'),('mdp.39015065704713','More acids and bases,','Davidson, David,1900-','1944-01-01'),('mdp.39015065705009','The Chemist at work,','Grady, Roy Israel,1890-ed.Chittum, John William,1901-joint ed.Reinmuth, Otto,1900-ed.','1940-01-01'),('mdp.39015065709746','The rare-earth elements.','Trifonov, D. N.(Dmitriĭ Nikolaevich)','1963-01-01'),('mdp.39015065724687','Mathematical foundations of statistical mechanics /','Khinchin, Aleksandr I︠A︡kovlevich,1894-1959.','1949-01-01'),('mdp.39015065728688','The analytical chemistry of indium.','Busev, A I','1962-01-01'),('mdp.39015065730494','Psycho-analysis for teachers and parents;','Freud, Anna,1895-1982.Low, Barbara,tr.','1935-01-01'),('mdp.39015065734439','Plant and stocks in the production of goods in seasonal demand.','Alessandro, Luigi d\',professor.','1963-01-01'),('mdp.39015065736251','The Indian capital market.','Cirvante, V R','1956-01-01'),('mdp.39015065750450','The international financial and banking crisis, 1913-1933,','Volpe, Paul A.(Paul Anthony),1915-1968.','1945-01-01'),('mdp.39015065759022','India;','Woytinsky, Wladimir S.1885-1960.','1957-01-01'),('mdp.39015065772751','Military chemistry and chemical agents.','United States.Army.Chemical corps.','1942-01-01'),('mdp.39015065808027','A window on Red Square /','Rounds, Frank,1915-','1953-01-01'),('mdp.39015065809306','Report submitted by the Legislative Research Council relative to State licensing and control of the use of tidelands.','Massachusetts.General Court.Legislative Research Bureau.Massachusetts.Legislative Reference Council.','1959-01-01'),('mdp.39015065897574','The sea /','Kellermann, Bernhard,1879-1951.','1924-01-01'),('mdp.39015065904917','Garibaldi and the new Italy ...','Huch, Ricarda Octavia,1864-1947.Phillips, Catherine Alison,Mrs.,1884-tr.','1928-01-01'),('mdp.39015066475594','New Russian stories /','Guerney, Bernard Guilbert,1894-comp. and tr.','1953-01-01'),('mdp.39015066496830','Stellar atmospheres:','Gaposchkin, Cecilia Helena Payne,1900-','1925-01-01'),('mdp.39015066500508','The dilemma of science /','Agar, William M.(William Macdonough),1894-','1941-01-01'),('mdp.39015066624472','Tales of laughter,','Wiggin, Kate Douglas Smith,1856-1923.ed.Smith, Nora Archibald,1859-1934.','1923-01-01'),('mdp.39015066904940','A layman\'s guide to the Texas State administrative agencies.','Smith, Dick,1908-','1945-01-01'),('mdp.39015066904957','Municipal electric utilities in Texas,','Gregory, Robert Henry.','1942-01-01'),('mdp.39015066905145','Texas planning, zoning, housing, park and airport laws ...','University of Texas.Institute of Public Affairs.Texas.Laws, statutes, etc.','1946-01-01'),('mdp.39015066905376','How bills become laws in Texas ...','Smith, Dick,1908-','1945-01-01'),('mdp.39015066927321','A translation of the map legends in the economic atlas of Japan (Nihon keizai chizu).','Zenkoku kyoiku tosho kabushiki kaisha, Tokyo.Aki, Koichi.Ginsburg, Norton Sydney.ed.Eyre, John D.(John Douglas),1922-ed.','1959-01-01'),('mdp.39015066986129','Slovnyk chuz︠h︡ozemnykh sliv =','Orel, Artem','1963-01-01'),('mdp.39015067139389','The foundations of geometry, /','Hilbert, David,1862-1943.Townsend, E. J.(Edgar Jerome),1864-1955','1947-01-01'),('mdp.39015067162431','The nature of life /','Rignano, Eugenio,1870-1930','1930-01-01'),('mdp.39015067163215','A contribution to the biology of Simulium (Diptera)','Wu, I-fang,1893-1985.','1931-01-01'),('mdp.39015067163801','Vneshni︠a︡i︠a︡ torgovli︠a︡ i vneshni︠a︡i︠a︡ torgovai︠a︡ politika Rossii.','Pokrovskiĭ, S. A.(Serafim Aleksandrovich)','1947-01-01'),('mdp.39015067225733','A guidebook of the justice of the peace,','Howerton, Huey Blair,1895-McIntire, Helen Hyde,1924-joint author.','1950-01-01'),('mdp.39015067225741','A guidebook of the county tax assessor.','Howerton, Huey Blair,1895-','1949-01-01'),('mdp.39015067255524','Lectures on Shakspeare, etc.','Coleridge, Samuel Taylor,1772-1834.','1930-01-01'),('mdp.39015067263346','English literature,','Carlton, W. N. C.(William Newnham Chattin),1873-1943.','1925-01-01'),('mdp.39015067265010','Your child\'s play:','Langdon, Grace,1889-','1957-01-01'),('mdp.39015067266315','The preschool child;','Crum, Grace E.Baldwin, Bird Thomas,1875-1928.Young child.American Library Association.','1929-01-01'),('mdp.39015067266323','The modern essay.','Crothers, Samuel McChord,1857-1927.American Library Association.','1926-01-01'),('mdp.39015067266331','The Pacific area in international relations,','Condliffe, J. B.(John Bell),1891-1981.','1931-01-01'),('mdp.39015067266349','The modern drama,','Clark, Barrett H.(Barrett Harper),1890-1953.American Library Association.','1927-01-01'),('mdp.39015067284144','Handbook for elected municipal officials in Idaho,','Lewis, William O.Pell, Katherine D.','1963-01-01'),('mdp.39015067308836','Renart le Bestorné','Ham, Edward Billings,1902-1965.','1947-01-01'),('mdp.39015067308844','Foreign influences on Middle English.','Price, Hereward Thimbleby,1880-1964.','1947-01-01'),('mdp.39015067308984','A new view of Congreve\'s Way of the world,','Mueschke, Paul,1899-Mueschke, Miriam,','1958-01-01'),('mdp.39015067308992','Les empereors de Rome;','Calendre,13th cent.Millard, Galia','1957-01-01'),('mdp.39015067309008','The complaint against hope,','Wilson, Kenneth G.(Kenneth George),1923-','1957-01-01'),('mdp.39015067309057','The contributions of John Wilkes to the Gazette littéraire de l\'Europe,','Wilkes, John,1725-1797.Bredvold, Louis I.(Louis Ignatius),b. 1888,ed.','1950-01-01'),('mdp.39015067331705','American water resources administration.','Shih, Yang-ch\'eng,1917-','1956-01-01'),('mdp.39015067331713','American water resources administration.','Shih, Yang-ch\'eng,1917-','1956-01-01'),('inu.32000009270911','Wilson\'s ideals,','Wilson, Woodrow,1856-1924.Padover, Saul Kussiel,1905-ed.American Council on Public Affairs.','1943-01-01'),('inu.32000009454499','World diary;','Howe, Quincy,1900-','1934-01-01'),('mdp.39015002012329','Some aspects of the luminescence of solids.','Kröger, F. A.','1948-01-01'),('mdp.39015008845565','A banker looks at book publishing.','Bound, Charles F.','1950-01-01'),('mdp.39015062745982','Introduction to educational psychology,','Hines, Harlan Cameron,1887-','1934-01-01'),('mdp.39015036839309','Selections from Hans Sachs,','Sachs, Hans,1494-1576.Calder, W. M.(William Moir),1881-1960.','1948-01-01'),('mdp.39015030435047','State control of labor disputes in connection with public service industries ...','Cross, Maurice Condit,1890-','1929-01-01'),('mdp.39015031929212','World peace is not a luxury,','Pipkin, Charles Wooten,1899-','1927-01-01'),('mdp.39015062922789','The French civil service: bureaucracy in transition,','Sharp, Walter Rice,1896-','1931-01-01'),('mdp.39015003998922','The Focal encyclopedia of photography.','','1957-01-01'),('mdp.39015059749112','The gem-hunters,','Rolt-Wheeler, Francis,1876-1960.','1924-01-01'),('mdp.39015011953240','Solving camp behavior problems;','Doherty, Ken,1905-','1940-01-01'),('mdp.39015059771884','The modern student: how to study in high school,','Berg, David Eric,1890-','1935-01-01'),('mdp.39015024037080','Second bibliography and catalogue of fossil Vertebrata of North America,','Hay, Oliver Perry,1846-1930.','1929-01-01'),('mdp.39015010300286','Our National Capital and its un-Americanized Americans.','Noyes, Theodore W.(Theodore Williams),1858-1946.','1951-01-01'),('mdp.39015058422356','France under the Bourbon Restoration, 1814-1830,','Artz, Frederick Binkerd.','1931-01-01'),('mdp.39015026830979','Heritage of American education /','Gross, Richard E.','1962-01-01'),('mdp.39015030621992','Unemployment of aliens in the United States, 1940.','Rubin, Ernest,1915-','1949-01-01'),('mdp.39015010432923','The design of electric circuits in the behavioral sciences.','Cornsweet, Tom N.','1963-01-01'),('mdp.39015058431860','The universe and life','Jennings, H. S.(Herbert Spencer),1868-1947.','1934-01-01'),('mdp.39015059740202','Partners with youth;','Roberts, Dorothy M.','1956-01-01'),('mdp.39015008834296','Support for independent scholarship and research;','Sibley, Elbridge,1903-1994.Social Science Research Council (U.S.)','1951-01-01'),('mdp.39015041295489','Inventory of the county archives of Maryland.','Historical Records Survey (U.S.).Maryland.','1937-01-01'),('mdp.39015063038650','What industries are subject to state and municipal operation;','United Typothetae of America.Department of research.La Salle Extension University.Department of research.Milwaukee typothetae inc.,pub.','1924-01-01'),('mdp.39015003397927','The basic aspects of radiation effects on living systems,','Symposium on Radiobiology,Oberlin College,1950.Nickson, James J.','1952-01-01'),('mdp.39015027781684','Back yonder;','Hogue, Wayman.Simon, Howard,1903-1979,ill.','1932-01-01'),('mdp.39015058623508','Fun mayn leben.','Medem, Vladimir,1879-1923.','1923-01-01'),('mdp.39015062314441','Classroom tests :','Russell, Charles,1893-1957.','1926-01-01'),('mdp.39015038826973','Studies on the fossil flora and fauna of the western United States.','Chaney, Ralph W.(Ralph Works),1890-1971.Miller, Loye Holmes,1874-Dice, Lee Raymond,1887-1977.','1925-01-01'),('mdp.39015030344827','ABC\'s for hospital librarians,','Pomeroy, Elizabeth Ella,1882-American Library Association.','1943-01-01'),('mdp.39015009284699','The Cartwright petition of 1649.','Cartwright, Johanna,fl. 1648.Cartwright, Ebenezer,fl. 1648.Schmulowitz, Nat,1889-Sutro Library.','1941-01-01'),('mdp.39015002946385','Practical ice making;','Authenrieth, Andrew J.,1866-Brandt, Emerson Andre,1903-joint author.','1931-01-01'),('mdp.39015031930475','A compilation of the resolutions on policy, third and fourth sessions of the UNRRA Council.','United Nations Relief and Rehabilitation Administration.Council.','1946-01-01'),('mdp.39015062382596','The fundamentals of Christianity;','Kent, Charles Foster,1867-1925.','1925-01-01'),('mdp.39015030021169','Labor and empire :','Tsiang, Tingfu F.(Tingfu Fuller),1895-1965.','1923-01-01'),('mdp.39015020470293','Siberia.','Lengyel, Emil,1895-','1943-01-01'),('mdp.39015002370248','Parapsychology, frontier science of the mind;','Rhine, J. B.(Joseph Banks),1895-1980.Pratt, J. Gaither(Joseph Gaither),1910-1979.joint author.','1957-01-01'),('mdp.39015030430121','Social security and life insurance ...','Cranefield, Paul Frederic,1897-1944.','1940-01-01'),('mdp.39015049200705','The Swinburne letters /','Swinburne, Algernon Charles,1837-1909.Lang, Cecil Y.,ed.Kerr, Evelyn,former owner.Kerr, Lowell,former owner.Yale University Press,publisher.Vail-Ballou Press,printer.','1959-01-01'),('mdp.39015005411536','Access and parking for institutions.','Smith, Wilbur Stevenson,1911-','1960-01-01'),('mdp.39015035853194','The kingdom of God and history /','Wood, H. G.(Herbert George),1879-1963.Dodd, C. H.(Charles Harold),1884-1973.','1938-01-01'),('mdp.39015028121955','Public library service to public school children;','Stallmann, Esther Laverne,1903-','1945-01-01'),('mdp.39015014507233','Manhattan pastures.','Hochman, Sandra.','1963-01-01'),('mdp.39015062190254','Argentina y los Estados Unidos,','Haring, Clarence Henry,1885-1960.Instituto Panamericano de Bibliografía y Documentación (Mexico)','1942-01-01'),('mdp.39015062201077','Man in Europe,','Jefferson, Mark Sylvester William,1863-1949.','1924-01-01'),('mdp.39015015211736','Albert Schweitzer:','Schweitzer, Albert,1875-1965.','1947-01-01'),('mdp.39015059457542','Lincoln the Hoosier;','Vannest, Charles Garrett.','1928-01-01'),('mdp.39015026741838','Monuments and men of ancient Rome,','Showerman, Grant,1870-1935.','1935-01-01'),('mdp.39015028137043','Publicity for public libraries;','Ward, Gilbert Oakley,1880-','1935-01-01'),('mdp.39015041300180','Inventory of the county archives of Alabama.','Alabama Historical Records Survey','1938-01-01'),('mdp.39015059721749','Craft projects for camp and playground.','National Recreation Association.','1959-01-01'),('mdp.39015059888506','The human perspective, being an interest theory of value ...','Williams, Gardner,1895-','1930-01-01'),('mdp.39015021107282','The seven skies,','Guggenheim, Harry Frank,1890-','1930-01-01'),('mdp.39015009005185','Chungking listening post,','Tennien, Mark A.Catholic Foreign Mission Society of America.','1945-01-01'),('mdp.39015004919166','The challenge of marriage,','Dreikurs, Rudolf,1897-1972.','1946-01-01'),('mdp.39015002565029','On love,','Stendhal,1783-1842.Holland, Vyvyan Beresford,1886-1967.tr.Scott-Moncrieff, C. K.(Charles Kenneth),1889-1930.','1947-01-01'),('mdp.39015068215824','Frequency modulation /','RCA Review.Goldsmith, Alfred N.(Alfred Norton),1888-1974.','1948-01-01'),('mdp.39015081950209','The compiled laws of the State of Michigan, 1948.','Michigan.Laws, statutes, etc.Mason Publishing Company.','1949-01-01'),('wu.89081503401','Television.','RCA Review.Goldsmith, Alfred N.(Alfred Norton),1888-1974ed.','1950-01-01'),('mdp.39015031324406','The clergy in civil defense.','United States.Federal Civil Defense Administration.','1951-01-01'),('mdp.39015069451147','Clarence D. Howe :','Hoover Medal Board of Award.','1952-01-01'),('mdp.39015027559288','Pet of the Met /','Freeman, Lydia.Freeman, Don.','1953-01-01'),('mdp.39015002153669','Complete stories of the great ballets /','Balanchine, George.','1954-01-01'),('mdp.39015049881074','\"Before I kill more ...\"','Freeman, Lucy,1916-','1955-01-01'),('uc1.b3843865','Hospital in action;','Freeman, Lucy,1916-','1956-01-01'),('mdp.39015064064036','White man, listen! /','Wright, Richard,1908-1960.','1957-01-01'),('mdp.39015043592511','The King of flesh and blood /','Shamir, Moshe,1921-2004.','1958-01-01'),('mdp.39015002586306','Troubled women,','Freeman, Lucy,1916-ed.','1959-01-01'),('uc1.b3146845','Selective bibliography for the study of English and American literature /','Altick, Richard Daniel,1915-Wright, Andrew,1923-2009joint author.','1960-01-01'),('uc1.b3480039','Herself surprised.','Cary, Joyce,1888-1957.Wright, Andrew,1923-2009.','1961-01-01'),('mdp.39015039837557','Advanced engineering mathematics.','Kreyszig, Erwin.','1962-01-01'),('mdp.39015084474140','How to plan your office layout;','National Stationery and Office Equipment Association (U.S.)','1953-01-01'),('mdp.39015056668489','Crowell\'s handbook of world opera.','Moore, Frank Ledlie.','1961-01-01'),('uc1.b3496576','Remember me to Tom,','Williams, Edwina Dakin.Freeman, Lucy,1916-','1963-01-01'),('mdp.39015002280678','Ford production methods,','Barclay, Hartley Wade,1903-','1936-01-01'),('uc1.b18463','Getting and earning,','Bye, Raymond T.(Raymond Taylor),b. 1892.Blodgett, Ralph H.(Ralph Hamilton),1905-','1937-01-01'),('wu.89081504193','Radio facsimile.','Goldsmith, Alfred N.(Alfred Norton),1888-1974ed.Callahan, John L.,1898-RCA Institutes.','1938-01-01'),('mdp.39015001400079','Table tennis comes of age,','Schiff, Sol.','1939-01-01'),('mdp.39015079843242','Census of manufactures: 1939.','United States.Bureau of the Census.','1940-01-01'),('inu.30000093904526','[University of Florida publications in experimental applied economics.','Sloan Project in Applied Economics.','1941-01-01'),('mdp.39015001587149','The letters of Abelard and Heloise,','Abelard, Peter,1079-1142.Héloïse,1101-1164.Scott-Moncrieff, C. K.(Charles Kenneth),1889-1930.tr.','1942-01-01'),('inu.32000011210418','A new home;','Kirkland, Caroline M.(Caroline Matilda),1801-1864.','1953-01-01'),('mdp.39015001871287','Ford.','Nevins, Allan,1890-1971.Hill, Frank Ernest,1888-1969.','1954-01-01'),('mdp.39015036889858','See and say, guarda e parla, mira y habla, regarde et parle;','Frasconi, Antonio.','1955-01-01'),('inu.30000081677589','The republic of Syria.','Patai, Raphael,1910-1996ed.Dropsie College for Hebrew and Cognate Learning.','1956-01-01'),('mdp.39015000348105','Gates of fear /','Conrad, Barnaby,1922-','1957-01-01'),('mdp.39015002835653','A history of Russian literature,','Mirsky, D. S.,Prince,1890-1939.Whitfield, Francis J.(Francis James),1916-1996.','1958-01-01'),('mdp.39015054057214','The eighteenth-century commonwealthman;','Robbins, Caroline.','1959-01-01'),('mdp.39015005024750','The affluent society.','Galbraith, John Kenneth,1908-2006.','1960-01-01'),('mdp.39015045987669','Nikolai Gogol /','Nabokov, Vladimir Vladimirovich,1899-1977.Parker, Fan,1908-former owner.Parker, Stephen,inscriber.Salter, Stefan,designer.New Directions Publishing Corp.,publisher.Vail-Ballou Press,printer.','1961-01-01'),('mdp.39015001455685','A proposal for the prevention and control of delinquency by expanding opportunities;','Mobilization for Youth.','1962-01-01'),('inu.30000083470769','Predicting success for university freshmen.','Chase, Clinton I.','1963-01-01'),('inu.32000002913582','The fascist movement in Italian life /','Gorgolini, Pietro,1891-Petre, Maude Dominica,1863-1942.','1923-01-01'),('inu.32000007729736','English society in the eighteenth century as influenced from oversea,','Botsford, Jay Barrett.','1924-01-01'),('inu.32000003495613','Essays in taxation.','Seligman, Edwin Robert Anderson,1861-1939.','1925-01-01'),('mdp.39015033916126','The North Texas regional libraries,','Kuhlman, Augustus Frederick,1889-','1943-01-01'),('mdp.39015084863839','The economics of the Pacific coast petroleum industry,','Bain, Joe Staten,1912-','1944-01-01'),('mdp.39015001429169','Basic writings of Saint Thomas Aquinas ...','Thomas,Aquinas, Saint,1225?-1274.Pegis, Anton Charles,1905-','1945-01-01'),('mdp.39015004084136','The stranger,','Camus, Albert,1913-1960.Gilbert, Stuart.tr.','1946-01-01'),('mdp.39015011352450','Catholic library practice.','Martin, David,Brother,1901-','1947-01-01'),('mdp.39015008655618','The age of reason.','Paine, Thomas,1737-1809.','1948-01-01'),('mdp.39015000363070','Eleven plays of Henrik Ibson;','Ibsen, Henrik,1828-1906.','1949-01-01'),('mdp.39015056952164','The happy time :','Taylor, Samuel,1912-2000.Fontaine, Robert Louis.Happy time.','1950-01-01'),('mdp.39015071455961','Commercial catalogs collection.','','1896-01-01'),('wu.89086255353','A treatise on pharmacy for students and pharmacists.','Caspari, Charles,1850-1917.Kelly, E. F.(Evander Francis),b. 1879.','1926-01-01');
UNLOCK TABLES;
/*!40000 ALTER TABLE `bibdata` ENABLE KEYS */;

--
-- Table structure for table `candidates`
--

DROP TABLE IF EXISTS `candidates`;
CREATE TABLE `candidates` (
  `id` varchar(32) NOT NULL default '',
  `time` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  `title` text,
  `author` text,
  `pub_date` date default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `candidates`
--


/*!40000 ALTER TABLE `candidates` DISABLE KEYS */;
LOCK TABLES `candidates` WRITE;
INSERT INTO `candidates` VALUES ('umn.31951000388825s','2010-02-14 21:30:04','Manual of Minnesota law.','Palmer, Benjamin W.(Benjamin Whipple),b. 1889.','1947-01-01'),('umn.31951000102994p','2010-02-14 21:30:04','A history of American magazines,','Mott, Frank Luther,1886-1964.','1957-01-01'),('umn.31951000942136r','2010-02-14 21:30:04','Selection of cotton fabrics. /','O\'Brien, Ruth,1892-','1926-01-01'),('umn.31951000473830n','2010-02-14 21:30:04','Drainage basin problems and programs.','United States.National Resources Committee.Water Resources Committee.Wolman, Abel,1892-','1938-01-01'),('inu.32000009966849','2010-02-14 21:30:04','The British Empire before the American Revolution,','Gipson, Lawrence Henry,1880-1971','1939-01-01'),('umn.31951000414021f','2010-02-14 21:30:04','Index of research projects ...','United States.Works Progress Administration.United States.National Resources Committee.','1938-01-01'),('inu.32000009457740','2010-02-14 21:30:04','Finland, its history and development :','For Finland, Inc.','1940-01-01'),('umn.31951000720765w','2010-02-14 21:30:04','Protective and decorative coatings.','Mattiello, Joseph J.,1900-United States.Army.Quartermaster Corps.','1945-01-01'),('umn.31951d03000617q','2010-02-14 21:30:08','The first Japanese diplomatic mission to the United States, 1860 /','Parks, E. Taylor.','1960-01-01'),('umn.31951d03000387h','2010-02-14 21:30:08','Employment of older women;','United States.Women\'s Bureau.','1957-01-01'),('umn.31951d029877130','2010-02-14 21:30:08','Classified index of occupations.','United States.Bureau of the Census.Edwards, Alba M.,1872-1947.Truesdell, Leon E.(Leon Edgar),1880-1979.','1930-01-01'),('umn.31951d030005221','2010-02-14 21:30:08','Conference workbook on problems of post-war higher education.','United States.Office of Education.','1944-01-01'),('umn.31951p00820264d','2010-02-14 21:30:09','Quill and beadwork of the western Sioux,','Lyford, Carrie A.(Carrie Alberta)','1940-01-01'),('umn.31951p00820094c','2010-02-14 21:30:09','The Commission on intergovernmental relations :','United States.Commission on Intergovernmental Relations.','1955-01-01'),('umn.31951p01092040v','2010-02-14 21:30:09','Fifteenth census of the United States: 1930 :','United States.Bureau of the Census.Truesdell, Leon E.(Leon Edgar),1880-1979.Arner, George B. Louis(George Byron Louis),1883-1952.','1931-01-01'),('umn.31951p008200968','2010-02-14 21:30:09','A study committee report on Federal aid to welfare, submitted to the Commission on Intergovernmental Relations.','United States.Commission on Intergovernmental Relations.Study Committee on Federal Aid to Welfare.','1955-01-01'),('umn.31951d030057054','2010-02-14 21:30:09','Point 4 in action;','United States.Dept. of the Interior.','1951-01-01'),('umn.31951p00820227j','2010-02-14 21:30:09','You and the United Nations, 1958-59 /','Lodge, Henry Cabot,1902-1985.','1958-01-01'),('umn.31951p00820046n','2010-02-14 21:30:09','Methodology involved in developing long-range cost estimates for the old-age, survivors, and disability insurance system.','Myers, Robert Julius,1912-','1959-01-01'),('wu.89013492269','2010-02-14 21:30:10','Shall strikes be outlawed?','Seidman, Joel Isaac,1906-Teper, Lazare,1908-','1938-01-01');
UNLOCK TABLES;
/*!40000 ALTER TABLE `candidates` ENABLE KEYS */;

--
-- Table structure for table `candidatesrecord`
--

DROP TABLE IF EXISTS `candidatesrecord`;
CREATE TABLE `candidatesrecord` (
  `time` timestamp NOT NULL default CURRENT_TIMESTAMP,
  `addedamount` int(11) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `candidatesrecord`
--


/*!40000 ALTER TABLE `candidatesrecord` DISABLE KEYS */;
LOCK TABLES `candidatesrecord` WRITE;
INSERT INTO `candidatesrecord` VALUES ('2010-02-02 14:17:48',3000),('2010-02-23 11:59:48',1),('2010-02-23 12:09:28',1),('2010-03-05 13:18:56',1),('2010-03-18 18:26:21',1),('2010-03-22 13:56:10',1),('2010-03-29 13:48:12',1);
UNLOCK TABLES;
/*!40000 ALTER TABLE `candidatesrecord` ENABLE KEYS */;

--
-- Table structure for table `duplicates`
--

DROP TABLE IF EXISTS `duplicates`;
CREATE TABLE `duplicates` (
  `id` varchar(32) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `duplicates`
--


/*!40000 ALTER TABLE `duplicates` DISABLE KEYS */;
LOCK TABLES `duplicates` WRITE;
UNLOCK TABLES;
/*!40000 ALTER TABLE `duplicates` ENABLE KEYS */;

--
-- Table structure for table `exportdata`
--

DROP TABLE IF EXISTS `exportdata`;
CREATE TABLE `exportdata` (
  `time` timestamp NOT NULL default CURRENT_TIMESTAMP,
  `id` varchar(32) default NULL,
  `attr` varchar(32) default NULL,
  `reason` varchar(32) default NULL,
  `user` varchar(32) default NULL,
  `src` varchar(32) default NULL,
  `gid` bigint(20) NOT NULL auto_increment,
  PRIMARY KEY  (`gid`),
  KEY `time_idx` (`time`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `exportdata`
--


/*!40000 ALTER TABLE `exportdata` DISABLE KEYS */;
LOCK TABLES `exportdata` WRITE;
UNLOCK TABLES;
/*!40000 ALTER TABLE `exportdata` ENABLE KEYS */;

--
-- Table structure for table `exportdataBckup`
--

DROP TABLE IF EXISTS `exportdataBckup`;
CREATE TABLE `exportdataBckup` (
  `time` timestamp NOT NULL default CURRENT_TIMESTAMP,
  `id` varchar(32) default NULL,
  `attr` varchar(32) default NULL,
  `reason` varchar(32) default NULL,
  `user` varchar(32) default NULL,
  `src` varchar(32) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `exportdataBckup`
--


/*!40000 ALTER TABLE `exportdataBckup` DISABLE KEYS */;
LOCK TABLES `exportdataBckup` WRITE;
UNLOCK TABLES;
/*!40000 ALTER TABLE `exportdataBckup` ENABLE KEYS */;

--
-- Table structure for table `exportrecord`
--

DROP TABLE IF EXISTS `exportrecord`;
CREATE TABLE `exportrecord` (
  `time` timestamp NOT NULL default CURRENT_TIMESTAMP,
  `itemcount` int(11) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Dumping data for table `exportrecord`
--


/*!40000 ALTER TABLE `exportrecord` DISABLE KEYS */;
LOCK TABLES `exportrecord` WRITE;
UNLOCK TABLES;
/*!40000 ALTER TABLE `exportrecord` ENABLE KEYS */;

--
-- Table structure for table `historicalreviews`
--

DROP TABLE IF EXISTS `historicalreviews`;
CREATE TABLE `historicalreviews` (
  `id` varchar(32) NOT NULL default '',
  `time` varchar(100) NOT NULL default '',
  `user` varchar(32) NOT NULL default '',
  `attr` tinyint(4) NOT NULL default '0',
  `reason` tinyint(4) NOT NULL default '0',
  `note` text,
  `renNum` varchar(12) default NULL,
  `expert` int(1) default NULL,
  `duration` varchar(10) default '00:00:00',
  `legacy` int(11) default '0',
  `expertNote` text,
  `renDate` varchar(12) default NULL,
  `copyDate` year(4) default NULL,
  `category` varchar(32) default NULL,
  `flagged` varchar(32) default NULL,
  `status` int(1) default '0',
  `priority` tinyint(4) NOT NULL default '0',
  `validated` tinyint(4) NOT NULL default '1',
  `source` varchar(32) NOT NULL default 'candidates',
  `gid` bigint(20) default NULL,
  `swiss` tinyint(1) NOT NULL default '0',
  PRIMARY KEY  (`id`,`time`,`user`),
  KEY `status_idx` (`status`),
  KEY `attr_idx` (`attr`),
  KEY `reason_idx` (`reason`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `historicalreviews`
--


/*!40000 ALTER TABLE `historicalreviews` DISABLE KEYS */;
LOCK TABLES `historicalreviews` WRITE;
INSERT INTO `historicalreviews` VALUES ('mdp.39015064503116','2008-06-25 12:00:00','cwilcox',5,8,'from German','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015064504643','2008-06-25 12:00:00','sgueva',5,8,'American Printing Industry Bulletin no. 1','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015064521340','2008-06-04 12:00:00','esaran',5,8,'copyright vested in U.S. Atty Gen.?','',0,'00:00:00',1,NULL,'',0000,'Misc',NULL,1,0,1,'legacy',NULL,0),('mdp.39015064535944','2008-06-18 12:00:00','gnichols',5,8,'Great Britain (1958)','',0,'00:00:00',1,NULL,'',0000,'Foreign Pub',NULL,1,0,1,'legacy',NULL,0),('mdp.39015064537056','2008-06-25 12:00:00','cwilcox',5,8,'from the German','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015064540944','2008-06-04 12:00:00','esaran',5,8,'copyright vested in U.S. Atty Gen.?','',0,'00:00:00',1,NULL,'',0000,'Misc',NULL,1,0,1,'legacy',NULL,0),('mdp.39015064543161','2008-06-24 12:00:00','cwilcox',5,8,'The Journal of English and Germanic Philology, vol. XLII, no. 2, April, 1943','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065132402','2008-06-26 12:00:00','cwilcox',5,8,'from? (by Alan Beesley)','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065134051','2008-06-26 12:00:00','esaran',5,8,'From Yiddish.','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065246095','2008-06-27 12:00:00','sgueva',5,8,'Unable to read language','',0,'00:00:00',1,NULL,'',0000,'Language',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065274550','2008-06-27 12:00:00','esaran',5,8,'From Russian.','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065294897','2008-06-27 12:00:00','sgueva',5,8,'Unable to read language','',0,'00:00:00',1,NULL,'',0000,'Language',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065311360','2008-06-27 12:00:00','esaran',5,8,'From Russian.','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065322946','2008-06-27 12:00:00','esaran',5,8,'From Russian.','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065378260','2008-06-26 12:00:00','cwilcox',5,8,'from the original Sanskrit','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065432463','2008-06-27 12:00:00','dfulmer',5,8,'The piece says copyright 1924, among other years. It may be that a part of this (it\'s the works of Mark Twain) needs to be checked for a renewal, since the title is simply Works, and there are no renewals for that.','',0,'00:00:00',1,NULL,'',0000,'Misc',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065432505','2008-06-24 12:00:00','dfulmer',5,8,'some essays by Mark Twain. Verso of title page lists many copyright dates, including 1928, but I think that may represent a renewal.','',0,'00:00:00',1,NULL,'',0000,'Insert(s)',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065432711','2008-06-06 12:00:00','esaran',5,8,'t.p. and copyright','',0,'00:00:00',1,NULL,'',0000,'Missing',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065452750','2008-06-04 12:00:00','esaran',5,8,'From French.','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065498217','2008-06-30 12:00:00','cwilcox',5,8,'from the Russian by Isabel F. Hapgood.','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065510052','2008-06-09 12:00:00','sgueva',5,8,'A translation of a 3 year collection of Radio Bremen talks','',0,'00:00:00',1,NULL,'',0000,'Insert(s)',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065510235','2008-06-24 12:00:00','gnichols',5,8,'various magazines incl. Daily Worker and Nature','',0,'00:00:00',1,NULL,'',0000,'Insert(s)',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065510284','2008-06-24 12:00:00','gnichols',5,8,'French (?)','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065511563','2008-06-04 12:00:00','sgueva',5,8,'Part of Chapter 1 from Popular Science, other portions from  multiple publications','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065512181','2008-06-13 12:00:00','sgueva',5,8,'Great Britian','',0,'00:00:00',1,NULL,'',0000,'Foreign Pub',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065512322','2008-06-12 12:00:00','sgueva',5,8,'Translated from German - 1950','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065512413','2008-06-12 12:00:00','sgueva',5,8,'German','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065516968','2008-06-17 12:00:00','dmcw',5,8,'Assessment Practice Series: no.2','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065528336','2008-06-03 12:00:00','sgueva',5,8,'Collection of reprinted stories from multiple publications','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065528617','2008-06-03 12:00:00','sgueva',5,8,'Essays reprinted from multiple publications','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065530274','2008-06-11 12:00:00','sgueva',5,8,'Includes a small collection of reprinted material from multiple publications','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065530282','2008-06-11 12:00:00','sgueva',5,8,'Russell Sage Foundation','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065530290','2008-06-11 12:00:00','sgueva',5,8,'The Menninger Clinic Monograph series no.9','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065531579','2008-06-24 12:00:00','sgueva',5,8,'State of New York Legislative Document no. 58','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065644430','2008-06-05 12:00:00','sgueva',5,8,'Russian translation','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065646955','2008-06-24 12:00:00','cwilcox',5,8,'from the Russian','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065654256','2008-06-09 12:00:00','sgueva',5,8,'Chemical News, London','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065655576','2008-06-03 12:00:00','sgueva',5,8,'Translated from the second and enlarged german edition','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065660857','2008-06-05 12:00:00','sgueva',5,8,'Augustana Library Publications no. 24','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065661939','2008-06-09 12:00:00','sgueva',5,8,'UN Doc','',0,'00:00:00',1,NULL,'',0000,'Misc',NULL,5,0,1,'legacy',NULL,0),('mdp.39015065668397','2008-06-11 12:00:00','sgueva',5,8,'Milbank Memorial Fund Quarterly 1960, 1961','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065671086','2008-06-17 12:00:00','dfulmer',5,8,'The Economics and Politics of Public Education 3','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065676309','2008-06-09 12:00:00','sgueva',5,8,'Volume also published as Spectrochimica Acta Vol. 14 (1958)','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065683149','2008-06-03 12:00:00','sgueva',5,8,'UN document.  No renewal found in Stanford','',0,'00:00:00',1,NULL,'',0000,'Misc',NULL,5,0,1,'legacy',NULL,0),('mdp.39015065683610','2008-06-09 12:00:00','sgueva',5,8,'Times Literary Supplement 1927','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065692769','2008-06-20 12:00:00','sgueva',5,8,'Studies in Public Administration no.15','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065692850','2008-06-25 12:00:00','esaran',5,8,'From German.','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065704713','2008-06-11 12:00:00','sgueva',5,8,'Contributions to chemical education number 3','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065705009','2008-06-25 12:00:00','gnichols',5,8,'Journal of Chemical Edication and a Symposium','',0,'00:00:00',1,NULL,'',0000,'Insert(s)',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065709746','2008-06-03 12:00:00','sgueva',5,8,'D.N. Trifnonov\'s book - Redkozemelnyye elementy, Moscow 1960','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065724687','2008-06-09 12:00:00','sgueva',5,8,'Russian translation','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065728688','2008-06-03 12:00:00','sgueva',5,8,'Additional series of monographs on analytical chemistry vol.5.  Translated from Russian','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065730494','2008-06-03 12:00:00','gnichols',5,8,'German?','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065734439','2008-06-19 12:00:00','dfulmer',5,8,'looks like this translation was published in London, original was Italian.','',0,'00:00:00',1,NULL,'',0000,'Foreign Pub',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065736251','2008-06-18 12:00:00','dfulmer',5,8,'University of Bombay Publications Economics Series, no.6, this also may be foreign but there is no notice of copyright.','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065750450','2008-06-26 12:00:00','dfulmer',5,8,'The Catholic University of America Studies in Economics v.9, this also may be linked to the wrong record, or this might be a different no. in a multinumber record (the title on the title page differs from the Mirlyn record.)','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065759022','2008-06-23 12:00:00','dfulmer',5,8,'portions of this book were originally published in The New Leader, 1956, though the book itself was not renewed.','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065772751','2008-06-19 12:00:00','esaran',5,8,'t.p. and copyright','',0,'00:00:00',1,NULL,'',0000,'Missing',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065808027','2008-06-02 12:00:00','dmcw',5,8,'contains various copyrighted selections','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065809306','2008-05-30 12:00:00','sgueva',5,8,'Commonwealth of massachusetts no. 2655','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065897574','2008-06-04 12:00:00','sgueva',5,8,'German','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065904917','2008-06-25 12:00:00','cwilcox',5,8,'from the German as: Der Kampf um Rom','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015066475594','2008-06-27 12:00:00','dfulmer',5,8,'England, plus it\'s a translation.','',0,'00:00:00',1,NULL,'',0000,'Foreign Pub',NULL,1,0,1,'legacy',NULL,0),('mdp.39015066496830','2008-06-20 12:00:00','esaran',5,8,'Harvard Observatory Monographs, No. 1','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015066500508','2008-06-06 12:00:00','sgueva',5,8,'Includes a collection of excerpts from multiple publications','',0,'00:00:00',1,NULL,'',0000,'Insert(s)',NULL,1,0,1,'legacy',NULL,0),('mdp.39015066624472','2008-06-03 12:00:00','sgueva',5,8,'Reprint of stories from numerous publications','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015066904940','2008-06-20 12:00:00','sgueva',5,8,'Municipal studies no. 22','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015066904957','2008-06-20 12:00:00','sgueva',5,8,'Munincipal studies no. 20','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015066905145','2008-06-20 12:00:00','sgueva',5,8,'Municipal studies no. 27','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015066905376','2008-06-20 12:00:00','sgueva',5,8,'Municipal studies no. 25','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015066927321','2008-06-18 12:00:00','dfulmer',5,8,'originally published in Tokyo in 1954.','',0,'00:00:00',1,NULL,'',0000,'Foreign Pub',NULL,1,0,1,'legacy',NULL,0),('mdp.39015066986129','2008-06-30 12:00:00','cwilcox',5,8,'Probably pn/ncn … Uncertain as to whether this is US pub or not (any Ukrainian speakers?)','',0,'00:00:00',1,NULL,'',0000,'Language',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067139389','2008-06-03 12:00:00','esaran',5,8,'of original 1902?','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067162431','2008-06-10 12:00:00','sgueva',5,8,'Unsure of translation language or year','',0,'00:00:00',1,NULL,'',0000,'Translation',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067163215','2008-06-10 12:00:00','esaran',5,8,'Papers of the Michigan Academy of Science, Arts and Letters, Vol. XIII, 1930. Published 1931.','',0,'00:00:00',1,NULL,'',0000,'Reprint',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067163801','2008-06-24 12:00:00','sgueva',5,8,'Can\'t read the language to find copyright information','',0,'00:00:00',1,NULL,'',0000,'Language',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067225733','2008-06-20 12:00:00','sgueva',5,8,'County government series no. 6','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067225741','2008-06-20 12:00:00','sgueva',5,8,'County government series no. 5','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067255524','2008-06-03 12:00:00','sgueva',5,8,'Everyman\'s Library no. 162','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067263346','2008-06-02 12:00:00','sgueva',5,8,'Reading with a purpose #2','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067265010','2008-06-24 12:00:00','sgueva',5,8,'Parent series number two','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067266315','2008-06-02 12:00:00','sgueva',5,8,'Reading with a purpose #38','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067266323','2008-06-02 12:00:00','sgueva',5,8,'Reading with a purpose #24','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067266331','2008-06-02 12:00:00','sgueva',5,8,'Reading with a purpose #44','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067266349','2008-06-02 12:00:00','sgueva',5,8,'Reading with a purpose #28','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067284144','2008-06-19 12:00:00','sgueva',5,8,'Public Affairs series no . 4','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067308836','2008-06-20 12:00:00','sgueva',5,8,'Contributions in modern philology no. 9','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067308844','2008-06-20 12:00:00','sgueva',5,8,'Contributions in modern philology no. 10','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067308984','2008-06-20 12:00:00','sgueva',5,8,'Contributions in modern philology num. 23','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067308992','2008-06-20 12:00:00','sgueva',5,8,'Contributions in modern philology number no. 22','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067309008','2008-06-20 12:00:00','sgueva',5,8,'Contributions in modern philolgy Number 21','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067309057','2008-06-20 12:00:00','sgueva',5,8,'Contributions in modern philology no. 15','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067331705','2008-06-04 12:00:00','sgueva',5,8,'American Water Resources Administration vol. II','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015067331713','2008-06-04 12:00:00','sgueva',5,8,'American Water Resources Administration vol. 1','',0,'00:00:00',1,NULL,'',0000,'Periodical',NULL,1,0,1,'legacy',NULL,0),('mdp.39015065661939','2008-11-10 12:00:00','annekz',1,2,'MISC: pd/ncn','',2,'00:00:00',1,NULL,'',0000,'Misc',NULL,5,0,1,'legacy',NULL,0),('mdp.39015024910328','2008-11-10 12:00:00','annekz',1,2,'MISC: pd/ncn','',2,'00:00:00',1,NULL,'',0000,'Misc',NULL,5,0,1,'legacy',NULL,0),('mdp.39015024912613','2008-11-10 12:00:00','annekz',1,2,'MISC: pd/ncn','',2,'00:00:00',1,NULL,'',0000,'Misc',NULL,5,0,1,'legacy',NULL,0),('mdp.39015010885039','2008-11-10 12:00:00','annekz',1,2,'MISC: pd/ncn','',2,'00:00:00',1,NULL,'',0000,'Misc',NULL,5,0,1,'legacy',NULL,0),('mdp.39015065683149','2008-11-10 12:00:00','annekz',1,2,'MISC: pd/ncn','',2,'00:00:00',1,NULL,'',0000,'Misc',NULL,5,0,1,'legacy',NULL,0),('mdp.39015023082301','2008-10-06 12:00:00','annekz',1,2,'MISC: not UN but pd/ncn anyway','',2,'00:00:00',1,NULL,'',0000,'Misc',NULL,5,0,1,'legacy',NULL,0);
UNLOCK TABLES;
/*!40000 ALTER TABLE `historicalreviews` ENABLE KEYS */;

--
-- Table structure for table `note`
--

DROP TABLE IF EXISTS `note`;
CREATE TABLE `note` (
  `note` text,
  `time` timestamp NOT NULL default CURRENT_TIMESTAMP
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `note`
--


/*!40000 ALTER TABLE `note` DISABLE KEYS */;
LOCK TABLES `note` WRITE;
INSERT INTO `note` VALUES ('REPLACE INTO reviews (id,user,attr,reason,note,renNum,renDate,category,priority,hold,expert,swiss) VALUES (\'uc1.b3911927\',\'moseshll\',1,7,NULL,NULL,NULL,NULL,0,\'NULL\',1,0)','2010-03-26 13:15:44'),('REPLACE INTO reviews (id,user,attr,reason,note,renNum,renDate,category,priority,hold,expert,swiss) VALUES (\'uc1.b3911927\',\'moseshll\',1,7,NULL,NULL,NULL,NULL,0,\'2010-03-30 23:59:59\',1,0)','2010-03-26 13:19:29'),('REPLACE INTO reviews (id,user,attr,reason,note,renNum,renDate,category,priority,hold,expert,swiss) VALUES (\'uc1.b3911927\',\'moseshll\',1,7,NULL,NULL,NULL,NULL,0,\'2010-03-30 23:59:59\',1,0)','2010-03-26 13:22:25'),('REPLACE INTO reviews (id,user,attr,reason,note,renNum,renDate,category,priority,hold,expert,swiss) VALUES (\'uc1.b3911927\',\'moseshll\',5,8,\'agrgdsd\',NULL,NULL,\'Dissertation/Thesis\',0,\'2010-03-30 23:59:59\',1,0)','2010-03-26 13:27:21'),('REPLACE INTO reviews (id,user,attr,reason,note,renNum,renDate,category,priority,hold,expert,swiss) VALUES (\'uc1.b3911927\',\'moseshll\',1,7,NULL,NULL,NULL,NULL,0,\'2010-03-30 23:59:59\',1,0)','2010-03-26 13:38:49'),('REPLACE INTO reviews (id,user,attr,reason,note,renNum,renDate,category,priority,hold,sticky_hold,expert,swiss) VALUES (\'uc1.b3911927\',\'moseshll\',1,7,NULL,NULL,NULL,NULL,0,NULL,\'2010-03-29 23:59:59\',1,0)','2010-03-26 13:40:12'),('REPLACE INTO reviews (id,user,attr,reason,note,renNum,renDate,category,priority,hold,expert,swiss) VALUES (\'uc1.b3911927\',\'moseshll\',1,7,NULL,NULL,NULL,NULL,0,\'2010-03-29 23:59:59\',1,0)','2010-03-26 13:46:59');
UNLOCK TABLES;
/*!40000 ALTER TABLE `note` ENABLE KEYS */;

--
-- Table structure for table `processstatus`
--

DROP TABLE IF EXISTS `processstatus`;
CREATE TABLE `processstatus` (
  `time` timestamp NOT NULL default CURRENT_TIMESTAMP
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Dumping data for table `processstatus`
--


/*!40000 ALTER TABLE `processstatus` DISABLE KEYS */;
LOCK TABLES `processstatus` WRITE;
UNLOCK TABLES;
/*!40000 ALTER TABLE `processstatus` ENABLE KEYS */;

--
-- Table structure for table `pubyearcycle`
--

DROP TABLE IF EXISTS `pubyearcycle`;
CREATE TABLE `pubyearcycle` (
  `pubyear` int(11) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Dumping data for table `pubyearcycle`
--


/*!40000 ALTER TABLE `pubyearcycle` DISABLE KEYS */;
LOCK TABLES `pubyearcycle` WRITE;
INSERT INTO `pubyearcycle` VALUES (1929);
UNLOCK TABLES;
/*!40000 ALTER TABLE `pubyearcycle` ENABLE KEYS */;

--
-- Table structure for table `queue`
--

DROP TABLE IF EXISTS `queue`;
CREATE TABLE `queue` (
  `id` varchar(32) NOT NULL default '',
  `time` timestamp NOT NULL default CURRENT_TIMESTAMP,
  `status` int(1) default '0',
  `pending_status` int(1) NOT NULL default '0',
  `locked` varchar(32) default NULL,
  `priority` int(1) default '0',
  `expcnt` int(11) default '0',
  `source` varchar(32) NOT NULL default 'candidates',
  PRIMARY KEY  (`id`),
  KEY `status_idx` (`status`),
  KEY `locked_idx` (`locked`),
  KEY `priority_idx` (`priority`),
  KEY `expcnt_idx` (`expcnt`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `queue`
--


/*!40000 ALTER TABLE `queue` DISABLE KEYS */;
LOCK TABLES `queue` WRITE;
INSERT INTO `queue` VALUES ('inu.32000009454499','2010-02-02 10:07:13',0,0,NULL,4,0,'adminui'),('mdp.39015071455961','2010-02-02 10:07:13',0,0,NULL,3,0,'adminui'),('inu.32000009270911','2010-02-02 10:07:13',0,0,NULL,4,0,'adminui'),('inu.32000003495613','2010-01-30 04:40:20',0,0,NULL,0,0,'candidates'),('mdp.39015001587149','2010-01-29 04:39:02',0,0,NULL,0,0,'candidates'),('inu.32000007729736','2010-01-30 04:40:20',0,0,NULL,0,0,'candidates'),('mdp.39015056952164','2010-02-02 05:02:53',0,0,NULL,0,0,'candidates'),('inu.32000002913582','2010-01-30 04:40:19',0,0,NULL,0,0,'candidates'),('mdp.39015000363070','2010-02-02 05:02:52',0,0,NULL,0,0,'candidates'),('inu.30000093904526','2010-01-29 04:39:02',0,0,NULL,0,0,'candidates'),('mdp.39015039837557','2010-01-28 04:41:24',0,0,NULL,0,0,'candidates'),('uc1.b3480039','2010-01-28 04:41:24',0,0,NULL,0,0,'candidates'),('mdp.39015079843242','2010-01-29 04:39:01',0,0,NULL,0,0,'candidates'),('inu.30000083470769','2010-01-30 04:39:49',0,0,NULL,0,0,'candidates'),('mdp.39015001455685','2010-01-30 04:39:49',0,0,NULL,0,0,'candidates'),('mdp.39015045987669','2010-01-30 04:39:48',0,0,NULL,0,0,'candidates'),('mdp.39015005024750','2010-01-30 04:39:47',0,0,NULL,0,0,'candidates'),('mdp.39015054057214','2010-01-30 04:39:47',0,0,NULL,0,0,'candidates'),('uc1.b3146845','2010-01-28 04:41:24',0,0,NULL,0,0,'candidates'),('mdp.39015008655618','2010-02-02 05:02:52',0,0,NULL,0,0,'candidates'),('mdp.39015002586306','2010-01-28 04:41:24',0,0,NULL,0,0,'candidates'),('mdp.39015002835653','2010-01-30 04:39:47',0,0,NULL,0,0,'candidates'),('mdp.39015043592511','2010-01-28 04:41:23',0,0,NULL,0,0,'candidates'),('uc1.b3496576','2010-01-28 04:42:19',0,0,NULL,0,0,'candidates'),('mdp.39015000348105','2010-01-30 04:39:46',0,0,NULL,0,0,'candidates'),('mdp.39015064064036','2010-01-28 04:41:23',0,0,NULL,0,0,'candidates'),('uc1.b3843865','2010-01-28 04:41:23',0,0,NULL,0,0,'candidates'),('mdp.39015049881074','2010-01-28 04:41:23',0,0,NULL,0,0,'candidates'),('inu.30000081677589','2010-01-30 04:39:46',0,0,NULL,0,0,'candidates'),('mdp.39015036889858','2010-01-30 04:39:45',0,0,NULL,0,0,'candidates'),('mdp.39015002153669','2010-01-28 04:41:23',0,0,NULL,0,0,'candidates'),('mdp.39015027559288','2010-01-28 04:41:22',0,0,NULL,0,0,'candidates'),('mdp.39015069451147','2010-01-28 04:41:22',0,0,NULL,0,0,'candidates'),('mdp.39015011352450','2010-02-02 05:02:52',0,0,NULL,0,0,'candidates'),('mdp.39015031324406','2010-01-28 04:41:22',0,0,NULL,0,0,'candidates'),('mdp.39015001871287','2010-01-30 04:39:44',0,0,NULL,0,0,'candidates'),('wu.89081503401','2010-01-28 04:41:22',0,0,NULL,0,0,'candidates'),('mdp.39015081950209','2010-01-28 04:41:22',0,0,NULL,0,0,'candidates'),('mdp.39015001400079','2010-01-29 04:39:00',0,0,NULL,0,0,'candidates'),('mdp.39015068215824','2010-01-28 04:41:22',0,0,NULL,0,0,'candidates'),('mdp.39015004084136','2010-02-02 05:02:52',0,0,NULL,0,0,'candidates'),('mdp.39015002012329','2010-02-01 14:33:59',0,0,NULL,3,0,'adminui'),('mdp.39015056668489','2010-01-28 04:42:19',0,0,NULL,0,0,'candidates'),('mdp.39015084474140','2010-01-28 04:42:15',0,0,NULL,0,0,'candidates'),('wu.89081504193','2010-01-29 04:39:00',0,0,NULL,0,0,'candidates'),('mdp.39015001429169','2010-02-02 05:02:52',0,0,NULL,0,0,'candidates'),('uc1.b18463','2010-01-29 04:38:59',0,0,NULL,0,0,'candidates'),('inu.32000011210418','2010-01-30 04:39:44',0,0,NULL,0,0,'candidates'),('mdp.39015002280678','2010-01-29 04:38:59',0,0,NULL,0,0,'candidates'),('mdp.39015002565029','2010-01-28 04:41:21',0,0,NULL,0,0,'candidates'),('mdp.39015004919166','2010-01-28 04:41:21',0,0,NULL,0,0,'candidates'),('mdp.39015084863839','2010-02-02 05:02:52',0,0,NULL,0,0,'candidates'),('mdp.39015009005185','2010-01-28 04:41:20',0,0,NULL,0,0,'candidates'),('mdp.39015008845565','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015062745982','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015036839309','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015030435047','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015031929212','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015062922789','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015003998922','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015059749112','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015011953240','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015059771884','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015024037080','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015010300286','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015058422356','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015026830979','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015030621992','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015010432923','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015058431860','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015059740202','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015008834296','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015041295489','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015063038650','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015003397927','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015027781684','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015058623508','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015062314441','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015038826973','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015030344827','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015033916126','2010-02-02 05:02:51',0,0,NULL,0,0,'candidates'),('mdp.39015009284699','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015002946385','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015031930475','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015062382596','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015030021169','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015020470293','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015002370248','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015030430121','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015049200705','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015005411536','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015035853194','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015028121955','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015014507233','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015062190254','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015062201077','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015015211736','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015059457542','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015026741838','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015028137043','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015041300180','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015059721749','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015059888506','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('mdp.39015021107282','2010-01-13 17:27:24',0,1,NULL,1,0,'rereport'),('wu.89086255353','2010-02-23 12:14:46',0,0,NULL,4,0,'adminui');
UNLOCK TABLES;
/*!40000 ALTER TABLE `queue` ENABLE KEYS */;

--
-- Table structure for table `queuerecord`
--

DROP TABLE IF EXISTS `queuerecord`;
CREATE TABLE `queuerecord` (
  `time` timestamp NOT NULL default CURRENT_TIMESTAMP,
  `itemcount` int(11) default NULL,
  `source` varchar(32) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Dumping data for table `queuerecord`
--


/*!40000 ALTER TABLE `queuerecord` DISABLE KEYS */;
LOCK TABLES `queuerecord` WRITE;
INSERT INTO `queuerecord` VALUES ('2010-02-23 12:14:46',1,'adminui');
UNLOCK TABLES;
/*!40000 ALTER TABLE `queuerecord` ENABLE KEYS */;

--
-- Table structure for table `renewals`
--

DROP TABLE IF EXISTS `renewals`;
CREATE TABLE `renewals` (
  `id` varchar(32) NOT NULL default '',
  `CopyrightYear` year(4) default NULL,
  `RenewalYear` year(4) default NULL,
  `Title` text,
  `Published` text,
  `Note` text,
  `Source` text,
  `Snippet` text,
  `all_names` text,
  `all_text` text,
  PRIMARY KEY  (`id`),
  FULLTEXT KEY `Title` (`Title`),
  FULLTEXT KEY `Published` (`Published`),
  FULLTEXT KEY `Note` (`Note`),
  FULLTEXT KEY `Source` (`Source`),
  FULLTEXT KEY `Snippet` (`Snippet`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `renewals`
--


/*!40000 ALTER TABLE `renewals` DISABLE KEYS */;
LOCK TABLES `renewals` WRITE;
UNLOCK TABLES;
/*!40000 ALTER TABLE `renewals` ENABLE KEYS */;

--
-- Table structure for table `reviews`
--

DROP TABLE IF EXISTS `reviews`;
CREATE TABLE `reviews` (
  `id` varchar(32) NOT NULL default '',
  `time` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  `user` varchar(32) NOT NULL default '',
  `attr` tinyint(4) NOT NULL default '0',
  `reason` tinyint(4) NOT NULL default '0',
  `note` text,
  `renNum` varchar(12) default NULL,
  `expert` int(1) default NULL,
  `duration` varchar(10) default '00:00:00',
  `legacy` int(11) default '0',
  `expertNote` text,
  `renDate` varchar(12) default NULL,
  `copyDate` year(4) default NULL,
  `category` varchar(32) default NULL,
  `flagged` varchar(32) default NULL,
  `priority` tinyint(4) NOT NULL default '0',
  `swiss` tinyint(1) NOT NULL default '0',
  `hold` timestamp NULL default NULL,
  `sticky_hold` timestamp NULL default NULL,
  PRIMARY KEY  (`id`,`user`),
  KEY `attr_idx` (`attr`),
  KEY `reason_idx` (`reason`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `reviews`
--


/*!40000 ALTER TABLE `reviews` DISABLE KEYS */;
LOCK TABLES `reviews` WRITE;
INSERT INTO `reviews` VALUES ('mdp.39015021107282','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015059888506','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015059721749','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015041300180','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015028137043','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015026741838','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015059457542','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015015211736','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015062201077','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015062190254','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015014507233','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015028121955','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015035853194','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015005411536','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015049200705','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015030430121','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015002370248','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015020470293','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015030021169','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015062382596','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015031930475','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015002946385','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015009284699','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015030344827','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015038826973','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015062314441','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015058623508','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015027781684','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015003397927','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015063038650','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015041295489','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015008834296','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015059740202','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015058431860','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015010432923','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015030621992','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015026830979','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015058422356','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015010300286','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015024037080','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015059771884','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015011953240','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015059749112','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015003998922','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015062922789','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015031929212','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015030435047','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015036839309','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015062745982','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL),('mdp.39015008845565','2010-02-02 14:07:49','rereport02',1,2,NULL,'',NULL,'00:00:00',0,NULL,'',NULL,'',NULL,1,0,NULL,NULL);
UNLOCK TABLES;
/*!40000 ALTER TABLE `reviews` ENABLE KEYS */;

--
-- Table structure for table `stanford`
--

DROP TABLE IF EXISTS `stanford`;
CREATE TABLE `stanford` (
  `ID` text NOT NULL,
  `DREG` varchar(10) default NULL,
  PRIMARY KEY  (`ID`(30))
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Dumping data for table `stanford`
--


/*!40000 ALTER TABLE `stanford` DISABLE KEYS */;
LOCK TABLES `stanford` WRITE;
UNLOCK TABLES;
/*!40000 ALTER TABLE `stanford` ENABLE KEYS */;

--
-- Table structure for table `stanford_full`
--

DROP TABLE IF EXISTS `stanford_full`;
CREATE TABLE `stanford_full` (
  `ID` text NOT NULL,
  `DATE` year(4) default NULL,
  `TITL` text,
  `AUTH` text,
  `OREG` varchar(10) default NULL,
  `DREG` varchar(10) default NULL,
  `ODAT` varchar(10) default NULL,
  `CLNA` text,
  `OCLS` varchar(10) default NULL,
  `EDST` text,
  `LINM` text,
  `SEST` text,
  `MISC` text,
  `XREF` text,
  `NOTE` text,
  `ADTI` text,
  `INAN` text,
  PRIMARY KEY  (`ID`(30))
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Dumping data for table `stanford_full`
--


/*!40000 ALTER TABLE `stanford_full` DISABLE KEYS */;
LOCK TABLES `stanford_full` WRITE;
UNLOCK TABLES;
/*!40000 ALTER TABLE `stanford_full` ENABLE KEYS */;

--
-- Table structure for table `systemstatus`
--

DROP TABLE IF EXISTS `systemstatus`;
CREATE TABLE `systemstatus` (
  `time` timestamp NOT NULL default CURRENT_TIMESTAMP,
  `status` varchar(32) default NULL,
  `message` text
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `systemstatus`
--


/*!40000 ALTER TABLE `systemstatus` DISABLE KEYS */;
LOCK TABLES `systemstatus` WRITE;
INSERT INTO `systemstatus` VALUES ('2010-02-23 12:10:31','normal','I am working on the test set, so the database is wonky. Please, no reviews.');
UNLOCK TABLES;
/*!40000 ALTER TABLE `systemstatus` ENABLE KEYS */;

--
-- Table structure for table `timer`
--

DROP TABLE IF EXISTS `timer`;
CREATE TABLE `timer` (
  `id` varchar(32) NOT NULL default '',
  `start_time` timestamp NOT NULL default '0000-00-00 00:00:00',
  `end_time` timestamp NOT NULL default '0000-00-00 00:00:00',
  `user` varchar(32) NOT NULL default '',
  PRIMARY KEY  (`id`,`user`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Dumping data for table `timer`
--


/*!40000 ALTER TABLE `timer` DISABLE KEYS */;
LOCK TABLES `timer` WRITE;
UNLOCK TABLES;
/*!40000 ALTER TABLE `timer` ENABLE KEYS */;

--
-- Table structure for table `und`
--

DROP TABLE IF EXISTS `und`;
CREATE TABLE `und` (
  `id` varchar(32) NOT NULL default '',
  `src` varchar(32) NOT NULL default '',
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `und`
--


/*!40000 ALTER TABLE `und` DISABLE KEYS */;
LOCK TABLES `und` WRITE;
UNLOCK TABLES;
/*!40000 ALTER TABLE `und` ENABLE KEYS */;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
CREATE TABLE `users` (
  `name` mediumtext NOT NULL,
  `type` tinyint(4) NOT NULL default '0',
  `id` varchar(12) NOT NULL default '',
  `alias` varchar(12) default NULL,
  PRIMARY KEY  (`id`,`type`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `users`
--


/*!40000 ALTER TABLE `users` DISABLE KEYS */;
LOCK TABLES `users` WRITE;
INSERT INTO `users` VALUES ('Dennis McWhinnie',1,'dmcw',''),('Chris Wilcox',1,'cwilcox','cwilcox123'),('David Fulmer',1,'dfulmer',''),('Senovia Guevara',1,'sgueva',''),('Judy Ahronheim',3,'jaheim','jaheim123'),('Greg Nichols',1,'gnichols','gnichols123'),('Greg Nichols',3,'gnichols','gnichols123'),('Anne Karle-Zenith',1,'annekz',''),('Anne Karle-Zenith',2,'annekz',''),('Anne Karle-Zenith',3,'annekz',''),('Moses User',1,'moseshll123',NULL),('Anne non-expert',3,'annekz-ne',NULL),('Greg Expert',3,'gnichols123',NULL),('Greg Expert',2,'gnichols123',NULL),('Greg Expert',1,'gnichols123',NULL),('Moses Hall',1,'moseshll',''),('Judy Expert',2,'jaheim123',NULL),('Rereport User',1,'rereport02',NULL),('Judy Expert',1,'jaheim123',NULL),('Judy Expert',3,'jaheim123',NULL),('Moses Hall',3,'moseshll',''),('Moses Hall',2,'moseshll',''),('Rereport User',1,'rereport01',NULL),('Judy Ahronheim',1,'jaheim','jaheim123'),('Anne non-expert',1,'annekz-ne',NULL),('Dennis McWhinnie',3,'dmcw',''),('Chris Wilcox',3,'cwilcox','cwilcox123'),('Dennis Expert',3,'dmcw123',NULL),('Dennis Expert',2,'dmcw123',NULL),('Dennis Expert',1,'dmcw123',NULL),('Chris Expert',3,'cwilcox123',NULL),('Chris Expert',2,'cwilcox123',NULL),('Chris Expert',1,'cwilcox123',NULL);
UNLOCK TABLES;
/*!40000 ALTER TABLE `users` ENABLE KEYS */;

--
-- Table structure for table `userstats`
--

DROP TABLE IF EXISTS `userstats`;
CREATE TABLE `userstats` (
  `user` varchar(32) NOT NULL default '',
  `month` varchar(2) default NULL,
  `year` varchar(4) default NULL,
  `monthyear` varchar(7) NOT NULL default '',
  `total_reviews` int(11) default NULL,
  `total_pd_ren` int(11) default NULL,
  `total_pd_cnn` int(11) default NULL,
  `total_pd_cdpp` int(11) default NULL,
  `total_pdus_cdpp` int(11) default NULL,
  `total_ic_ren` int(11) default NULL,
  `total_ic_cdpp` int(11) default NULL,
  `total_und_nfi` int(11) default NULL,
  `total_time` int(11) default NULL,
  `time_per_review` double default NULL,
  `reviews_per_hour` double default NULL,
  `total_outliers` int(11) default NULL,
  PRIMARY KEY  (`user`,`monthyear`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `userstats`
--


/*!40000 ALTER TABLE `userstats` DISABLE KEYS */;
LOCK TABLES `userstats` WRITE;
UNLOCK TABLES;
/*!40000 ALTER TABLE `userstats` ENABLE KEYS */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;

