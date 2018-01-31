#!/bin/bash -e

wd=$(dirname $0)
source ${wd}/ecs-utils.sh
eval $(getServiceConfigs)
for k in "${!hofa[@]}" ; do
    options=$(echo "${hofa[$k]}" | sed -e 's/|/ --service-configs /g')
    ecs-cli compose -p '' -f $STATEDIR/docker-compose.$STACK.json service ps$options 2>&1 | grep -v "Skipping unsupported YAML"
done

