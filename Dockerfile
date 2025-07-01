FROM debian:trixie

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
  perl \
  wget

RUN cpanm --notest \
  Devel::Cover::Report::Coveralls \
  MARC::Record::MiJ

ENV SDRROOT /htapps/babel
ENV ROOTDIR "${SDRROOT}/crms"
RUN mkdir -p $ROOTDIR
COPY . $ROOTDIR
WORKDIR $ROOTDIR

ENV NODE_VERSION 22

# install nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# set env
ENV NVM_DIR=/root/.nvm

# install node
RUN bash -c "source $NVM_DIR/nvm.sh && nvm install $NODE_VERSION"

# install dependencies
RUN bash -c "source $NVM_DIR/nvm.sh && npm ci && npm run build"


# set ENTRYPOINT for reloading nvm-environment
ENTRYPOINT ["bash", "-c", "source $NVM_DIR/nvm.sh && exec \"$@\"", "--"]
