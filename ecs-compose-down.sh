#!/bin/bash -euxE

source $(dirname $0)/ecs-utils.sh

eval $(getServiceConfigs)

declare -A extant
for service in $(aws ecs list-services --cluster $STACK | jq -r '.serviceArns | .[]'); do
    extant+=([-$(basename $service)]=1)
done

for k in "${!hofa[@]}" ; do
    options=$(echo "${hofa[$k]}" | sed -e 's/|/ --service-configs /g')
    svcname=$(echo "${hofa[$k]}" | sed -e 's/|/-/g')
    if test "${extant[$svcname]+isset}"; then
      ecs-cli compose -p '' -f ${STATEDIR}/docker-compose.${STACK}.json service down$options
    fi
done

for service in $(aws ecs list-services --cluster $STACK | jq -r '.serviceArns | .[]'); do
    aws ecs delete-service --cluster $STACK --service $service
done

for olddef in $(aws ecs list-task-definitions | jq -r ' .taskDefinitionArns | .[] ') ; do
    aws ecs deregister-task-definition --task-definition $olddef
done
