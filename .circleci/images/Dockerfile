FROM circleci/golang:1.10
ARG aws_region=us-east-2
MAINTAINER dick <noreply@shunyet.com>
RUN set -xe \
  && sudo apt-get -yq update \
  && DEBIAN_FRONTEND=noninteractive sudo apt-get -yq install jq gawk netcat-openbsd rsync python-pip vim \
  && sudo apt-get clean \
  && sudo rm -rf /var/lib/apt/lists/* \
  && sudo pip install awscli jinja2 ruamel.yaml redis jsonnet s3cmd boto3 botocore Jinja2 six yq gitpython \
  && aws configure set region $aws_region
