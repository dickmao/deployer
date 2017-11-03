#!/bin/bash -exu

wd=$(dirname $0)
STATEDIR="${wd}/ecs-state"
if [ ! -d $STATEDIR ]; then
    mkdir $STATEDIR
fi

VERNUM=${1:-0}
VERNUM=$(printf "%04d" $VERNUM)
STACK=ecs-$(whoami)-${VERNUM}

TASKDEF=$(aws ecs describe-services --cluster $STACK --services $(basename `pwd`) | jq -r ' .services[0] | .taskDefinition ')
if [ "$TASKDEF" != "null" ]; then
    aws ecs deregister-task-definition --task-definition $TASKDEF
fi

if aws cloudformation describe-stacks --stack-name $STACK 2>/dev/null ; then
    aws cloudformation delete-stack --stack-name $STACK
    inprog=0
    while [ $inprog -lt 10 ] && [ "DELETE_IN_PROGRESS" == $(aws cloudformation describe-stacks --stack-name $STACK | jq -r ' .Stacks[0] | .StackStatus ') ]; do
        echo DELETE_IN_PROGRESS...
        let inprog=inprog+1
        sleep 10
    done
fi
if [[ "ACTIVE" == $(aws ecs describe-clusters --cluster $STACK | jq -r ' .clusters[0] | .status') ]] ; then
    aws ecs delete-cluster --cluster $STACK
fi
if [ ! -e $STATEDIR/$VERNUM ]; then
    echo WARN No record of $VERNUM in $STATEDIR
else
    rm $STATEDIR/$VERNUM
fi
