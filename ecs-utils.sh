#!/bin/bash -eu

if ! aws configure get region; then
  aws configure set region ${AWS_REGION}
fi

function set_circle_token {
  if [ -f ${wd}/circleci.api ]; then
    CIRCLE_TOKEN=$(cat ${wd}/circleci.api)
  fi
  if [ -z ${CIRCLE_TOKEN:-} ] ; then
    echo Need CIRCLE_TOKEN api token enviroment variable
    exit -1
  fi
  if [ -z ${CIRCLE_BUILD_NUM:-} ] ; then
    echo Need CIRCLE_BUILD_NUM environment variable
    exit -1
  fi
}

function down_all {
  set_circle_token
  VERNUMS=$(curl -sku ${CIRCLE_TOKEN}: https://circleci.com/api/v1.1/project/github/dickmao/deployer?limit=100 | jq -r ".[] | select(.branch==\"${CIRCLE_BRANCH}\") | \"\(.workflows | .workflow_id[-4:])\"" | sort -u)
  local result=0
  IFS=$'\n'
  for vernum in $VERNUMS; do
    if aws ecs describe-clusters --cluster $(get-cluster $vernum) | jq -r '.clusters[] | select(.status=="ACTIVE") | .clusterName' | grep $vernum ; then
      if ! ${wd}/ecs-down.sh $vernum ; then
        echo Error downing $vernum
        result=1
      fi
    fi
  done
  unset IFS
  return $result
}

function set_circleci_vernum {
  set_circle_token
  VERNUM=$(curl -sku ${CIRCLE_TOKEN}: https://circleci.com/api/v1.1/project/github/dickmao/deployer | jq -r ".[] | select(.build_num==${CIRCLE_BUILD_NUM}) | .workflows | .workflow_id[-4:]" )
  IFS=$'\n'
  REUSE=$(curl -sku ${CIRCLE_TOKEN}: https://circleci.com/api/v1.1/project/github/dickmao/deployer | jq -r ".[] | select(.branch==\"${CIRCLE_BRANCH}\") | \"\(.outcome) \(.workflows | .workflow_id[-4:])\"" | uniq )
  for reuse in $REUSE; do
    local status
    local vernum
    status="${reuse% *}"
    vernum="${reuse#* }"
    if ( [ $status == "failed" ] || [ $status == "canceled" ] ) && aws ecs describe-clusters --cluster $(get-cluster $vernum) | jq -r '.clusters[] | select(.status=="ACTIVE") | .clusterName' | grep $vernum ; then
      VERNUM=$vernum
      return 1
      break
    fi
  done
  unset IFS
  return 0
}

wd=$(dirname $0)
source ${wd}/bash_aliases.sh
STATEDIR="${wd}/ecs-state"
if [ ! -d $STATEDIR ]; then
  mkdir $STATEDIR
fi
VERNUM=${1:-$(get-vernum)}
STACK=$(get-cluster $VERNUM)

function render_string {
  mode=${1:-dev}
  if [ -z "${GIT_USER:-}" ] || [ -z "${GIT_PASSWORD-}" ]; then
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
    unset IFS
  
    GIT_USER="${aa['username']}"
    GIT_PASSWORD="${aa['password']}"
  fi
  SES_USER=${SES_USER:-$(aws configure --profile ses get aws_access_key_id)}
  SES_PASSWORD=${SES_PASSWORD:-$(aws configure --profile ses get aws_secret_access_key)}
  local GIT_BRANCH
  GIT_BRANCH=$(git rev-parse --verify --quiet --abbrev-ref HEAD)
  if [ -z $GIT_BRANCH ]; then
    GIT_BRANCH="dev"
  fi
  local EIP_ADDRESS
  EIP_ADDRESS=$(aws cloudformation list-exports | jq -r '.Exports[] | select((.Name | startswith("'$STACK'")) and (.Name | endswith("PlayAppEIP"))) | .Value')
  if [ $mode == "ecs" ] && [ -z $EIP_ADDRESS ]; then
    echo Warn Could not find PlayAppEIP for $STACK
  fi
  python render-docker-compose.py $mode --var cluster=$STACK --var GIT_USER=${GIT_USER} --var GIT_PASSWORD=${GIT_PASSWORD} --var AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id) --var AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key) --var AWS_DEFAULT_REGION=$(aws configure get region) --var MONGO_AUTH_STRING="admin:password@" --var SES_USER=${SES_USER} --var SES_PASSWORD=${SES_PASSWORD} --var GIT_BRANCH=${CIRCLE_BRANCH:-${GIT_BRANCH}} --var EIP_ADDRESS=${EIP_ADDRESS}
}

function getServiceConfigs {
  eval $(getTaskConfigs)
  declare -A hofa
  for s0 in $(docker-compose -p '' -f $STATEDIR/docker-compose.$STACK.json config --services); do
      s0p=${s0%%[![:alnum:]]*}
      if ! test "${hofb[$s0p]+isset}"; then
          if test "${hofa[$s0p]+isset}"; then
              hofa[$s0p]="${hofa[$s0p]}|$s0"
          else
              hofa+=([$s0p]="|$s0")
          fi
      fi
  done
  declare -p hofa
}

function getTaskConfigs {
  declare -A hofb
  for s0 in $(cat ${wd}/ecs-params.yml | yq -r '.task_definition | .services | to_entries[] | select(.value.task == true) | .key'); do
      s0p=${s0%%[![:alnum:]]*}
      if test "${hofb[$s0p]+isset}"; then
          hofb[$s0p]="${hofb[$s0p]}|$s0"
      else
          hofb+=([$s0p]="|$s0")
      fi
  done
  declare -p hofb
}
