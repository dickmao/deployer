#!/bin/bash -euxE

ecs-cli compose service down
for olddef in $(aws ecs list-task-definitions | jq -r ' .taskDefinitionArns | .[] ') ; do
    aws ecs deregister-task-definition --task-definition $olddef
done
