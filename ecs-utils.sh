#!/bin/bash -eu

if ! aws configure get region; then
  aws configure set region ${AWS_REGION}
fi

function set_circleci_vernum {
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
  VERNUM=$(curl -sku ${CIRCLE_TOKEN}: https://circleci.com/api/v1.1/project/github/dickmao/deployer | jq -r ".[] | select(.build_num==${CIRCLE_BUILD_NUM}) | .workflows | .workflow_id[-4:]" )

  IFS=$'\n'
  REUSE=$(curl -sku ${CIRCLE_TOKEN}: https://circleci.com/api/v1.1/project/github/dickmao/deployer | jq -r ".[] | select(.branch==\"${CIRCLE_BRANCH}\") | \"\(.outcome) \(.workflows | .workflow_id[-4:]) \"" | uniq )
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
if [ -z $VERNUM ]; then
  echo No outstanding clusters found
  exit -1
fi
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
  python render-docker-compose.py $mode --var cluster=$STACK --var GIT_USER=${GIT_USER} --var GIT_PASSWORD=${GIT_PASSWORD} --var AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id) --var AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key) --var AWS_DEFAULT_REGION=$(aws configure get region) --var MONGO_AUTH_STRING="admin:password@" --var SES_USER=${SES_USER} --var SES_PASSWORD=${SES_PASSWORD} --var CIRCLE_BRANCH=${CIRCLE_BRANCH:-}
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
