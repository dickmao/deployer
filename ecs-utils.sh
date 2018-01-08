#!/bin/bash -eu

wd=$(dirname $0)
STATEDIR="${wd}/ecs-state"
if [ ! -d $STATEDIR ]; then
    mkdir $STATEDIR
fi

VERNUM=${1:-0}
if [ $VERNUM == 0 ]; then
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
STACK=ecs-$(whoami)-${VERNUM}

function render_string {
  mode=${1:-dev}
  python render-docker-compose.py $mode --var cluster=$STACK --var AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id) --var AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key) --var AWS_DEFAULT_REGION=$(aws configure get region)
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