#!/bin/bash -euxE

source $(dirname $0)/ecs-utils.sh

eval $(getServiceConfigs)

for k in "${!hofa[@]}" ; do
    options=$(echo "${hofa[$k]}" | sed -e 's/|/ --service-configs /g')
    ecs-cli compose -f ${wd}/docker-compose.yml -f ${STATEDIR}/docker-compose.${STACK}.yml service down$options
done

for service in $(aws ecs list-services --cluster $STACK | jq -r '.serviceArns | .[]'); do
    aws ecs delete-service --cluster $STACK --service $service
done

for olddef in $(aws ecs list-task-definitions | jq -r ' .taskDefinitionArns | .[] ') ; do
    aws ecs deregister-task-definition --task-definition $olddef
done
