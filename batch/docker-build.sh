#!/bin/bash -ex

while [[ $# -gt 0 ]] ; do
  key="$1"
  case "$key" in
      -s|--scratch)
      scratch=1
      shift
      ;;
      *)
      break
      ;;    
  esac
done

cd $(dirname $0)

function build_fit() {
  if [ ! -z $(docker ps -aq --filter "name=fit") ]; then
    docker rm -f $(docker ps -aq --filter "name=fit")
  fi
  if [ -d ".python-stanford-corenlp" ]; then
    (cd .python-stanford-corenlp ; git pull )  
  else
    git clone --depth=1 --single-branch git@github.com:dickmao/python-stanford-corenlp.git .python-stanford-corenlp
  fi
  if [ -d ".fit" ]; then
    (cd .fit ; git pull )  
  else
    git clone --depth=1 --single-branch git@github.com:dickmao/fit.git .fit
  fi
  COPY=""
  for file in $( cd .fit ; git ls-files ) ; do
    dir=$(dirname $file)
    COPY=$(printf "$COPY\nCOPY .fit/${file} /${dir}/")
  done

  cat > ./Dockerfile.fit <<EOF
FROM python:2.7
MAINTAINER dick <noreply@shunyet.com>
RUN apt-get -yq update && \
    apt-get -y install libenchant1c2a && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN pip install nltk requests numpy pytz gensim python_dateutil pyenchant scikit_learn awscli s3cmd
RUN aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID && \
    aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY && \
    aws configure set region $AWS_REGION
COPY .python-stanford-corenlp /python-stanford-corenlp
RUN cd /python-stanford-corenlp && \
    python setup.py install
$COPY
ENTRYPOINT [ "python", "fit.py", "--corenlp-uri", "http://corenlp:9005" ]
EOF

  ../ecr-build-and-push.sh ./Dockerfile.fit fit:latest
}

function build_jobdef() {
  if [ ! -z $(docker ps -aq --filter "name=jobdef") ]; then
    docker rm -f $(docker ps -aq --filter "name=jobdef")
  fi

  cat > ./Dockerfile.jobdef <<EOF
FROM alpine:latest
MAINTAINER dick <noreply@shunyet.com>
RUN apk --update add py-pip bash docker && \
  pip install docker-compose awscli && \
  aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID && \
  aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY && \
  aws configure set region $AWS_REGION
COPY docker-login-compose.sh /
COPY docker-compose.yml /
ENTRYPOINT ["./docker-login-compose.sh", "up"]
EOF

  ../ecr-build-and-push.sh ./Dockerfile.jobdef jobdef:latest
}

function build_corenlp() {
  if [ ! -z $(docker ps -aq --filter "name=corenlp") ]; then
    docker rm -f $(docker ps -aq --filter "name=corenlp")
  fi

  gradle -p ./CoreNLP distDocker
}

set +x
# IAM roles can be set but I want to be able to run fit locally
AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
AWS_REGION=$(aws configure get region)
set -x
build_jobdef
build_fit
build_corenlp
