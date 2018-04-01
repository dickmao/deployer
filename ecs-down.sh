#!/bin/bash -exu

while [[ $# -gt 0 ]] ; do
  key="$1"
  case "$key" in
      --nosnap)
      shift
      nosnap=1
      ;;
      *)
      break
      ;;    
  esac
done

source $(dirname $0)/ecs-utils.sh

function clean_state {
  if [ -z ${CIRCLE_BUILD_NUM:-} ]; then
      if [ ! -e $STATEDIR/$VERNUM ]; then
          echo WARN No record of $VERNUM in $STATEDIR
      else
          rm $STATEDIR/$VERNUM
      fi
  fi
}

if ! aws cloudformation describe-stacks --stack-name $STACK 2>/dev/null ; then
  echo Stack $STACK not found
  clean_state
  exit 0
fi



TASKDEF=$(aws ecs describe-services --cluster $STACK --services $(basename `pwd`) | jq -r ' .services[0] | .taskDefinition ')
if [ "$TASKDEF" != "null" ]; then
  aws ecs deregister-task-definition --task-definition $TASKDEF
fi

IFS=$'\n'
for trailarn in $(aws cloudformation describe-stack-resources --stack-name $STACK | jq -r '.StackResources[] | select(.ResourceType=="AWS::CloudTrail::Trail") | .PhysicalResourceId'); do
  # the question is though, will this *flush* whatever has yet to be written to bucket
  aws cloudtrail stop-logging --name $trailarn || true
done
unset IFS

for bucket in $(aws cloudformation describe-stack-resources --stack-name $STACK |jq -r '.StackResources | map(select(.ResourceType=="AWS::S3::Bucket")) | .[] | .PhysicalResourceId '); do
  aws s3 rm s3://$bucket/ --recursive || true
done

if [ -z ${nosnap:-} ]; then
  python ${wd}/ebs-snapshot-scheduler/ebs-snapshot-scheduler.py --nodry $STACK
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
clean_state
for lg in $(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$STACK" | jq -r '.logGroups[] | .logGroupName '); do
    aws logs delete-log-group --log-group-name $lg
done
