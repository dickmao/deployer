#!/bin/bash -euxE

function finish {
    if [ $? != 0 ]; then
        $(dirname $0)/batch-down.sh
    fi
}
function sigH {
    trap '' ERR # don't sigH again for the imminent "false"
    false # -e makes it go to finish
}

trap finish EXIT
trap sigH INT TERM ERR QUIT

function wait_finish() {
  stack=$1
  inprog=0
  while [ $inprog -lt 60 ] && [ "xCREATE_IN_PROGRESS" == "x$(aws cloudformation describe-stacks --stack-name $stack 2>/dev/null | jq -r ' .Stacks[0] | .StackStatus ')" ]; do
      echo CREATE_IN_PROGRESS...
      let inprog=inprog+1
      sleep 10
  done
}

BUCKET=303634175659.newyork

aws cloudformation create-stack --stack-name aws-batch --template-body file://base.yaml --capabilities CAPABILITY_NAMED_IAM --parameters \
ParameterKey=S3Bucket,ParameterValue=${BUCKET}

wait_finish 'aws-batch'

declare -A outputs
for kv in $(aws cloudformation describe-stacks --stack-name aws-batch | jq -r ' .Stacks[] | .Outputs[] | "\(.OutputKey)=\(.OutputValue)" '); do
    IFS='=' read -r -a array <<< $kv
    echo ${array[0]} = ${array[1]}
    outputs+=([${array[0]}]="${array[1]}")
done
declare -p outputs

ACCOUNTID=303634175659
REGION=$(aws configure get region)
SERVICEROLE="${outputs['AWSBatchServiceRole']}"
IAMFLEETROLE="${outputs['AmazonEC2SpotFleetRole']}"
#INSTANCEROLE=$(aws iam get-instance-profile --instance-profile-name $(basename ${outputs['BatchInstanceProfile']}) | jq -r ' .InstanceProfile | .Roles[0] | .Arn ')
INSTANCEROLE="${outputs['BatchInstanceProfile']}"
JOBROLE="${outputs['BatchJobRole']}"
TOPIC="${outputs['SNSTopic']}"

SUBNETS="${outputs['PublicSubnet1']},${outputs['PublicSubnet2']}"
SECGROUPS="${outputs['SecurityGroup']}"
SPOTPER=40
AMI=$(aws ec2 describe-images --owners amazon --filter="Name=name,Values=*-ecs-optimized" | jq -r '.Images[] | "\(.Name)\t\(.ImageId)"' | sort -r | head -1 | cut -f2)
KEYNAME=dick
MINCPU=0
MAXCPU=1024
DESIREDCPU=0
RETRIES=1
REGISTRY=${ACCOUNTID}.dkr.ecr.${REGION}.amazonaws.com
IMAGE=${REGISTRY}/jobdef
ENV=env0

# Be sure to escape SubnetIds and SecurityGroupIds as they require a basestring and not a list
aws cloudformation create-stack --stack-name aws-batch-queues --template-body file://batch_env.template.yaml --parameters \
ParameterKey=BatchServiceRole,ParameterValue=${SERVICEROLE} \
ParameterKey=SpotIamFleetRole,ParameterValue=${IAMFLEETROLE} \
ParameterKey=InstanceRole,ParameterValue=${INSTANCEROLE} \
ParameterKey=JobRole,ParameterValue=${JOBROLE} \
ParameterKey=SubnetIds,ParameterValue=\"${SUBNETS}\" \
ParameterKey=SecurityGroupIds,ParameterValue=\"${SECGROUPS}\" \
ParameterKey=BidPercentage,ParameterValue=${SPOTPER} \
ParameterKey=ImageId,ParameterValue=${AMI} \
ParameterKey=KeyPair,ParameterValue=${KEYNAME} \
ParameterKey=MinvCpus,ParameterValue=${MINCPU} \
ParameterKey=DesiredvCpus,ParameterValue=${DESIREDCPU} \
ParameterKey=MaxvCpus,ParameterValue=${MAXCPU} \
ParameterKey=Env,ParameterValue=${ENV} \
ParameterKey=RetryNumber,ParameterValue=${RETRIES} \
ParameterKey=DockerImage,ParameterValue=${IMAGE} \
ParameterKey=MySNSTopic,ParameterValue=${TOPIC} \

wait_finish 'aws-batch-queues'

POLICY=$(aws sns get-topic-attributes --topic-arn $TOPIC | jq -r '.Attributes | .Policy' )
STATEMENT=$(echo $POLICY | jq -c '.Statement[] ')
read -r -a sids <<<$STATEMENT
SIDS=$(IFS=, ; echo "${sids[*]}")
VERSION=$(echo $POLICY | jq -c '.Version')
ID=$(echo $POLICY | jq -c '.Id')
aws sns set-topic-attributes --topic-arn $TOPIC --attribute-name Policy --attribute-value "{\"Version\":$VERSION,\"Id\":$ID,\"Statement\":[$SIDS,{\"Sid\":\"Allow_Publish_Events\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"events.amazonaws.com\"},\"Action\":\"sns:Publish\",\"Resource\":\"${TOPIC}\"}]}"
# EVENT=$(aws events list-rule-names-by-target --target-arn $TOPIC | jq -r ' .RuleNames[] ')
# EVPAT=$(aws events describe-rule --name $EVENT  | jq  -r '.EventPattern')
# aws events put-rule --name $EVENT --event-pattern "$EVPAT"

