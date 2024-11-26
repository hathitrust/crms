FROM debian:bullseye

RUN sed -i 's/main.*/main contrib non-free/' /etc/apt/sources.list

RUN apt-get update && apt-get install -y \
  perl \
  libxerces-c3.2 \
  libxerces-c3-dev \
  sqlite3 \
  file \
  libalgorithm-diff-xs-perl \
  libapache-session-perl \
  libarchive-zip-perl \
  libcapture-tiny-perl \
  libcgi-application-perl \
  libcgi-psgi-perl \
  libclass-c3-perl \
  libclass-data-accessor-perl \
  libclass-data-inheritable-perl \
  libclass-errorhandler-perl \
  libclass-load-perl \
  libcompress-raw-zlib-perl \
  libconfig-auto-perl \
  libconfig-inifiles-perl \
  libconfig-tiny-perl \
  libdata-optlist-perl \
  libdata-page-perl \
  libdate-calc-perl \
  libdate-manip-perl \
  libdbd-mock-perl \
  libdbd-mysql-perl \
  libdbd-sqlite3-perl \
  libdigest-sha-perl \
  libemail-date-format-perl \
  libencode-locale-perl \
  libexcel-writer-xlsx-perl \
  libfcgi-perl \
  libfcgi-procmanager-perl \
  libfile-listing-perl \
  libfile-slurp-perl \
  libfilesys-df-perl \
  libgeo-ip-perl \
  libhtml-parser-perl \
  libhtml-tree-perl \
  libhttp-browserdetect-perl \
  libhttp-cookies-perl \
  libhttp-daemon-perl \
  libhttp-date-perl \
  libhttp-dav-perl \
  libhttp-message-perl \
  libhttp-negotiate-perl \
  libinline-perl \
  libio-html-perl \
  libio-socket-ssl-perl \
  libio-string-perl \
  libipc-run-perl \
  libjson-perl \
  libjson-pp-perl \
  libjson-xs-perl \
  liblist-moreutils-perl \
  liblog-log4perl-perl \
  liblwp-authen-oauth2-perl \
  liblwp-mediatypes-perl \
  libmail-sendmail-perl \
  libmailtools-perl \
  libmarc-record-perl \
  libmarc-xml-perl \
  libmime-lite-perl \
  libmime-types-perl \
  libmodule-implementation-perl \
  libmodule-runtime-perl \
  libmoose-perl \
  libmouse-perl \
  libnet-dns-perl \
  libnet-http-perl \
  libparse-recdescent-perl \
  libplack-perl \
  libspreadsheet-writeexcel-perl \
  libtemplate-perl \
  libterm-readkey-perl \
  libterm-readline-gnu-perl \
  libtest-simple-perl \
  libtimedate-perl \
  libtry-tiny-perl \
  liburi-encode-perl \
  libuuid-perl \
  libuuid-tiny-perl \
  libversion-perl \
  libwww-perl \
  libxml-dom-perl \
  libxml-libxml-perl \
  libxml-libxslt-perl \
  libxml-sax-perl \
  libxml-simple-perl \
  libxml-writer-perl \
  libyaml-appconfig-perl \
  libyaml-libyaml-perl \
  libyaml-perl

RUN apt-get install -y \
  autoconf \
  bison \
  build-essential \
  cpanminus \
  git \
  libdevel-cover-perl \
  libffi-dev \
  libgdbm-dev \
  libperl-critic-perl \
  libreadline6-dev \
  libsqlite3-dev \
  libssl-dev \
  libyaml-dev

RUN cpanm --notest \
  Devel::Cover::Report::Coveralls \
  MARC::Record::MiJ \
  Test::Exception \
  Test::LWP::UserAgent

ENV SDRROOT /htapps/babel
ENV ROOTDIR "${SDRROOT}/crms"
RUN mkdir -p $ROOTDIR
COPY . $ROOTDIR
WORKDIR $ROOTDIR
