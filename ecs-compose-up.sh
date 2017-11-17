#!/bin/bash -euxE

declare -A only=()
while [[ $# -gt 0 ]] ; do
  key="$1"
  case "$key" in
      -s|--service-prefix)
      only+=([$2]=1)
      shift
      shift
      ;;
      *)
      break
      ;;    
  esac
done

wd=$(dirname $0)
source ${wd}/ecs-utils.sh

rendered_string=$(python render-docker-compose.py ecs --var cluster=$STACK --var AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id) --var AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key) --var AWS_DEFAULT_REGION=$(aws configure get region)))
printf "$rendered_string" > $STATEDIR/docker-compose.$STACK.json

eval $(getServiceConfigs)

for olddef in $(aws ecs list-task-definitions | jq -r ' .taskDefinitionArns | .[] ') ; do
    bn=$(basename $olddef)
    td=${bn%:*}
    svc=${td#*-}
    svc=${svc%%-*}
    if [ ${#only[@]} -eq 0 ] || test "${only[$svc]+isset}" ; then
        aws ecs deregister-task-definition --task-definition $olddef
    fi
done

for k in "${!hofa[@]}" ; do
    options=$(echo "${hofa[$k]}" | sed -e 's/|/ --service-configs /g')
    if [ ${#only[@]} -eq 0 ] || test "${only[$k]+isset}"; then
        ecs-cli compose -p '' -f $STATEDIR/docker-compose.$STACK.json service up$options
    fi
done
