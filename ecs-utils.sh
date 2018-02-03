#!/bin/bash -eu

if [ -z "$(aws configure get region)" ]; then
  aws configure set region ${AWS_REGION}
fi

function set_circleci_user_vernum {
  # Lionel: how-to-check-if-a-variable-is-set-in-bash
  if [ -f ${wd}/circleci.api ]; then
    CIRCLE_TOKEN=$(cat ${wd}/circleci.api)
  fi
  if [ -z $CIRCLE_TOKEN ] ; then
    echo Need CIRCLE_TOKEN api token enviroment variable
    exit -1
  fi
  if [ -z $CIRCLE_BUILD_NUM ] ; then
    echo Need CIRCLE_BUILD_NUM enviroment variable
    exit -1
  fi
  VERNUM=$(curl -sku ${CIRCLE_TOKEN}: https://circleci.com/api/v1.1/project/github/dickmao/deployer | jq -r ".[] | select(.build_num==${CIRCLE_BUILD_NUM}) | .workflows | .workflow_id" | tail -c 5)
  USER="circleci"
}

wd=$(dirname $0)
STATEDIR="${wd}/ecs-state"
if [ ! -d $STATEDIR ]; then
  mkdir $STATEDIR
fi

if [ ! -z $CIRCLE_BUILD_NUM ]; then
  set_circleci_user_vernum
else  
  USER=$(whoami)
  VERNUM=${1:--1}
  if [ $VERNUM == -1 ]; then
    read -r -a array <<< $(cd $STATEDIR ; ls -1 [0-9][0-9][0-9][0-9] 2>/dev/null)
    if [ ${#array[@]} == 1 ]; then
      VERNUM=${array[0]}
    elif [ ${#array[@]} -gt 1 ] ; then
      echo Which one? ${array[@]}
      exit -1
    else
      echo No outstanding clusters found
      exit -1
    fi
  fi
  VERNUM=$(printf "%04d" $VERNUM)
fi
STACK=ecs-${USER}-${VERNUM}

function render_string {
  mode=${1:-dev}
  if [ -z "$GIT_USER" ] || [ -z "$GIT_PASSWORD" ]; then
    declare -A aa
    IFS=$'\n'
    for kv in $(cat <<EOF | git credential fill
protocol=https
host=github.com
EOF
    ); do
      k="${kv%=*}"
      v="${kv#*=}"
      aa+=([$k]="$v")
    done
  
    GIT_USER="${aa['username']}"
    GIT_PASSWORD="${aa['password']}"
  fi
  python render-docker-compose.py $mode --var cluster=$STACK --var GIT_USER=${GIT_USER} --var GIT_PASSWORD=${GIT_PASSWORD} --var AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id) --var AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key) --var AWS_DEFAULT_REGION=$(aws configure get region)
}

function getServiceConfigs {
  declare -A hofa
  for s0 in $(docker-compose -p '' -f $STATEDIR/docker-compose.$STACK.json config --services); do
      s0p=${s0%%[![:alnum:]]*}
      if test "${hofa[$s0p]+isset}"; then
          hofa[$s0p]="${hofa[$s0p]}|$s0"
      else
          hofa+=([$s0p]="|$s0")
      fi
  done
  declare -p hofa
}
