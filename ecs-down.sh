#!/bin/bash -exu

source $(dirname $0)/ecs-utils.sh

if aws cloudformation describe-stacks --stack-name $STACK 2>/dev/null ; then
  TASKDEF=$(aws ecs describe-services --cluster $STACK --services $(basename `pwd`) | jq -r ' .services[0] | .taskDefinition ')
  if [ "$TASKDEF" != "null" ]; then
    aws ecs deregister-task-definition --task-definition $TASKDEF
  fi
fi
# https://alestic.com/2016/09/aws-route53-wipe-hosted-zone/
hosted_zone_id=$(
  aws route53 list-hosted-zones \
    --output json \
    --query "HostedZones[?Name==\`$STACK.internal.\`].Id" | jq -r '.[0] | select(.!=null)' \
)
if [ ! -z ${hosted_zone_id} ]; then
  aws route53 list-resource-record-sets --hosted-zone-id $hosted_zone_id | jq -c '.ResourceRecordSets[]' | \
  while read -r resourcerecordset; do
    read -r name type <<<$(echo $(jq -r '.Name,.Type' <<<"$resourcerecordset"))
    if [ $type != "NS" -a $type != "SOA" ]; then
      aws route53 change-resource-record-sets \
        --hosted-zone-id $hosted_zone_id \
        --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet":
            '"$resourcerecordset"'
          }]}' \
        --output text --query 'ChangeInfo.Id'
    fi
  done
  aws route53 delete-hosted-zone \
    --id $hosted_zone_id \
    --output text --query 'ChangeInfo.Id'
fi

if aws cloudformation describe-stacks --stack-name $STACK 2>/dev/null ; then
    aws cloudformation delete-stack --stack-name $STACK
    inprog=0
    while [ $inprog -lt 50 ] && [ "xDELETE_IN_PROGRESS" == "x$(aws cloudformation describe-stacks --stack-name $STACK 2>/dev/null | jq -r ' .Stacks[0] | .StackStatus ')" ]; do
        echo DELETE_IN_PROGRESS...
        let inprog=inprog+1
        sleep 10
    done
fi
if [[ "ACTIVE" == $(aws ecs describe-clusters --cluster $STACK | jq -r ' .clusters[0] | .status') ]] ; then
    aws ecs delete-cluster --cluster $STACK
fi
if [ -z $CIRCLE_BUILD_NUM ]; then
  if [ ! -e $STATEDIR/$VERNUM ]; then
      echo WARN No record of $VERNUM in $STATEDIR
  else
      rm $STATEDIR/$VERNUM
  fi
fi
