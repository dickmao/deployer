FROM circleci/golang:1.9.2
MAINTAINER dick <noreply@shunyet.com>
RUN set -xe \
  && sudo apt-get -yq update \
  && DEBIAN_FRONTEND=noninteractive sudo apt-get -yq install jq gawk netcat-openbsd rsync python-pip vim \
  && sudo apt-get clean \
  && sudo rm -rf /var/lib/apt/lists/* \
  && sudo pip install awscli jinja2 rua.yaml jsonnet
