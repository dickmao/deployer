#!/bin/bash -euxE

function finish {
    if [ $? != 0 ]; then
        ${wd}/ecs-down.sh $VERNUM
    fi
}
function sigH {
    trap '' ERR # don't sigH again for the imminent "false"
    false # -e makes it go to finish
}

trap finish EXIT
trap sigH INT TERM ERR QUIT

# :patrik, stackoverflow
containsElement () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

wd=$(dirname $0)
STATEDIR="${wd}/ecs-state"
if [ ! -d $STATEDIR ]; then
    mkdir $STATEDIR
fi

read -r -a states <<< $(cd $STATEDIR ; echo 0000 [0-9][0-9][0-9][0-9] | gawk '/\y[0-9]{4}\y/ { print $1 }' RS=" " | sort -n)
for s in ${states[@]} ; do
    VERNUM=$(echo $s | sed 's/^0*//')
    VERNUM=$(expr $VERNUM + 1)
    VERNUM=$(printf "%04d" $VERNUM)
    if ! containsElement $VERNUM ${states[@]} ; then
        break
    fi
done
VERNUM=${VERNUM:-0001}
touch $STATEDIR/$VERNUM

STACK=ecs-$(whoami)-${VERNUM}
KEYFORNOW=dick
if ! aws ec2 describe-key-pairs --key-names $KEYFORNOW; then
    echo Keypair "${KEYFORNOW}" needs to be manually uploaded
fi
ecs-cli configure --cfn-stack-name="$STACK" --cluster "$STACK" --region "us-east-2"
IMAGE=$(aws ec2 describe-images --owners amazon --filter="Name=name,Values=*-ecs-optimized" | jq -r '.Images[] | "\(.Name)\t\(.ImageId)"' | sort -r | head -1 | cut -f2)
ecs-cli template --instance-type t2.micro --force --cluster "$STACK" --image-id $IMAGE --template "./dns.template" --keypair dick --capability-iam --size 2
#INFO=$(aws cloudformation describe-stack-resources --stack-name "$STACK")
#VPC=$(echo $INFO | jq -r ' .StackResources | .[] | select(.ResourceType=="AWS::EC2::VPC") | .PhysicalResourceId ')
#SG=$(echo $INFO | jq -r ' .StackResources | .[] | select(.ResourceType=="AWS::EC2::SecurityGroup") | .PhysicalResourceId ')
# aws ec2 authorize-security-group-ingress --group-id ${SG} --protocol tcp --port 22 --cidr 0.0.0.0/0
# aws route53 create-hosted-zone --name servicediscovery.internal --hosted-zone-config Comment="Hosted Zone for ECS Service Discovery" --vpc VPCId=$VPC,VPCRegion=$(aws configure get region) --caller-reference $(date +%s)
