FROM debian:trixie

ARG UNAME=crms
ARG UID=1000
ARG GID=1000

RUN apt-get update && apt-get install -y \
  cpanminus \
  file \
  git \
  libcapture-tiny-perl \
  libcgi-pm-perl \
  libdata-page-perl \
  libdate-calc-perl \
  libdate-manip-perl \
  libdbd-mysql-perl \
  libdevel-cover-perl \
  libfile-slurp-perl \
  libipc-run-perl \
  libjson-xs-perl \
  liblog-log4perl-perl \
  liblwp-mediatypes-perl \
  libmail-sendmail-perl \
  libnet-http-perl \
  libperl-critic-perl \
  libtemplate-perl \
  libtest-exception-perl \
  libtest-lwp-useragent-perl \
  libtimedate-perl \
  libtry-tiny-perl \
  liburi-encode-perl \
  libuuid-perl \
  libuuid-tiny-perl \
  libwww-perl \
  libxml-libxml-perl \
  libyaml-perl \
  libmarc-record-perl \
  libmarc-xml-perl \
  nodejs \
  npm \
  perl

RUN cpanm --notest \
  Devel::Cover::Report::Coveralls \
  MARC::Record::MiJ

ENV SDRROOT /htapps/babel
ENV ROOTDIR "${SDRROOT}/crms"

RUN groupadd -g $GID -o $UNAME
RUN useradd -m -d $ROOTDIR -u $UID -g $GID -o -s /bin/bash $UNAME
RUN chmod 755 $ROOTDIR

USER $UNAME
WORKDIR $ROOTDIR

COPY --chown=crms:crms . $ROOTDIR

RUN npm ci
RUN npm run build
