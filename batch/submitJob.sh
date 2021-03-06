#!/bin/bash -exuE

declare -A params=()
while [[ $# -gt 0 ]] ; do
  key="$1"
  case "$key" in
      --queue)
      params+=([queue]=$2)
      shift
      shift
      ;;
      --args)
      params+=([args]=$2)
      shift
      shift
      ;;
      *)
      break
      ;;
  esac
done

ACCOUNTID=303634175659
SCRIPT=${1:-${HOME}/scrapy/fit.py}
SCRIPT=$(realpath $SCRIPT)
cd $(dirname $0)
QUEUE=${params[queue]:-hi}
ARGS=${params[args]:-}
BASENAME=$(basename $SCRIPT)
TAG=${BASENAME%.*}
VERNUM=$(echo $BASENAME | sed -n 's/.*\([0-9]\{4,5\}\).*/\1/p')
cp -f $SCRIPT ./.${BASENAME}

function get_latest {
  echo $(docker images -q  --filter=reference="$1:$2*" --format "{{.Repository}}:{{.Tag}}" | head -1)
}

function build_aws_jobdef {
  REGISTRY=${ACCOUNTID}.dkr.ecr.${AWS_REGION}.amazonaws.com
  declare -A outputs
  for kv in $(aws cloudformation describe-stacks --stack-name aws-batch | jq -r ' .Stacks[] | .Outputs[] | "\(.OutputKey)=\(.OutputValue)" '); do
      IFS='=' read -r -a array <<< $kv
      echo ${array[0]} = ${array[1]}
      outputs+=([${array[0]}]="${array[1]}")
  done
  declare -p outputs
  JOBROLE="${outputs['BatchJobRole']}"

  cat > ./jobdef.json <<EOF
{
    "jobDefinitionName": "$TAG",
    "type": "container",
    "containerProperties": {
        "image": "${REGISTRY}/jobdef:${TAG}",
        "vcpus": 2,
        "memory": 5000,
        "jobRoleArn": "$JOBROLE",
        "volumes": [{
            "host": {"sourcePath": "/var/run/docker.sock"},
            "name": "dind"
        },{
            "name": "docker_scratch"
        }],
        "mountPoints": [{
            "containerPath": "/var/run/docker.sock",
            "readOnly": false,
            "sourceVolume": "dind"
        },{
            "containerPath": "/scratch",
            "readOnly": false,
            "sourceVolume": "docker_scratch"
        }],
        "privileged": true
    },
    "retryStrategy": {"attempts": 1}
}
EOF
  JOBDEFARN=$(aws batch register-job-definition --job-definition-name $TAG --type container --cli-input-json file://jobdef.json | jq -r ' .jobDefinitionArn ')
}

function push_image_fit {
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

  IFS=' ' read -ra args <<< $ARGS
  if [ ${#args[@]} -eq 0 ]; then
    EARGS=""
  else
    EARGS=$(printf ', "%s"' "${args[@]}")
  fi

  cat > ./Dockerfile.fit <<EOF
FROM python:2.7
MAINTAINER dick <noreply@shunyet.com>
RUN apt-get -yq update && \
    apt-get -y install libenchant1c2a libblas-common libblas-dev libblas3 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN pip install nltk requests numpy pytz gensim matplotlib python_dateutil && \
    pip install pyenchant awscli Cython && \
    python -m nltk.downloader punkt && \
    aws configure set region $AWS_REGION
$COPY
COPY .$BASENAME /$BASENAME
COPY python-stanford-corenlp /python-stanford-corenlp
RUN pip install --user -e /python-stanford-corenlp
COPY scikit-learn /scikit-learn
RUN pip install --user -e /scikit-learn
ENTRYPOINT [ "python", "$BASENAME"$EARGS ]
EOF

  $(dirname $0)/../ecr-build-and-push.sh ./Dockerfile.fit fit:$TAG
}

function push_image_jobdef {
  cat > ./Dockerfile.jobdef <<EOF
FROM alpine:latest
MAINTAINER dick <noreply@shunyet.com>
RUN apk --update add python3 bash docker && \
  pip3 install docker-compose awscli && \
  aws configure set region $AWS_REGION
COPY docker-login-compose.sh /
COPY docker-compose.yml /
ENTRYPOINT ["./docker-login-compose.sh", "$TAG"]
EOF

  $(dirname $0)/../ecr-build-and-push.sh ./Dockerfile.jobdef jobdef:$TAG
}

function construct_compose {
  cat > ./docker-compose.yml <<EOF
# DO NOT EDIT.  Dynamic from submitJob.sh
---
version: "2"
services: 
  corenlp: 
    image: "${ACCOUNTID}.dkr.ecr.${AWS_REGION}.amazonaws.com/corenlp:3.8.0"
    stdin_open: true
    tty: true
    ports: 
      - "9005"
    volumes: 
      - "docker_scratch:/scratch"
  fit:
    image: "${ACCOUNTID}.dkr.ecr.${AWS_REGION}.amazonaws.com/fit:${TAG}"
    stdin_open: true
    tty: true
    volumes: 
      - "docker_scratch:/scratch"
volumes: 
    docker_scratch: null
EOF
}

set +x
# IAM roles can be set but I want to be able to run fit locally
AWS_REGION=$(aws configure get region)
set -x
construct_compose
push_image_jobdef
push_image_fit
build_aws_jobdef

for kv in $(aws batch describe-job-queues | jq -r ' .jobQueues[] | "\(.jobQueueName)=\(.jobQueueArn)" '); do
  IFS='=' read -r -a array <<< $kv
  if [[ "${array[0]}" == *"${QUEUE}"* ]]; then
    QARN=${array[1]}
  else
    QARN=${QARN:-${array[1]}}
  fi
done


aws batch submit-job --job-name $TAG --job-queue $QARN --job-definition $JOBDEFARN
