#!/bin/bash -euxE

function finish {
  if [ $? != 0 ]; then
    if [ ! -z "$(aws ecs describe-clusters --cluster $STACK | jq -r ' .clusters[]')" ] ; then
      ${wd}/ecs-down.sh $VERNUM
    fi
  fi
}
function sigH {
    trap '' ERR # don't sigH again for the imminent "false"
    false # -e makes it go to finish
}

trap finish EXIT
trap sigH INT TERM ERR QUIT

function render {
    python ${wd}/render-template.py --region $REGION --outdir /var/tmp "$@"
}

function refresh_templates {
    base=$1
    s3cmd mb  s3://${ACCOUNT}.templates --region $REGION 2> /dev/null || [ $? == 13 ]
    render $base
    s3cmd put /var/tmp/$base s3://${ACCOUNT}.templates/$base --region $REGION 

    IFS=$'\n'
    for s3key in $(cat /var/tmp/$base | jq -cr '.. | .Code? // empty | .S3Key '); do
        zipfile=$(basename $s3key)
        dir=${zipfile%%\.*}
        if git ls-files --error-unmatch $dir 2>/dev/null 1>/dev/null; then
            s3cmd mb  s3://${ACCOUNT}.zips --region $REGION 2> /dev/null || [ $? == 13 ]
            (rm -f /var/tmp/$dir.zip ; cd $dir ; git ls-files . | zip -r /var/tmp/$dir -@ )
            s3cmd put /var/tmp/$dir.zip s3://${ACCOUNT}.zips/$dir.zip --region $REGION 
        fi
    done
    for url in $(cat /var/tmp/$base | jq -cr '.. | .TemplateURL? // empty'); do
        template=$(basename $url)
        template=${template%%\"*}
        if git ls-files --error-unmatch $template 2>/dev/null 1>/dev/null; then
            refresh_templates $template
        fi
    done
    unset IFS
}

# :patrik, stackoverflow
containsElement () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

ACCOUNT=$(aws sts get-caller-identity --output text --query 'Account')
REGION=$(aws configure get region)
wd=$(dirname $0)
source ${wd}/ecs-utils.sh 0
if [ ! -z ${CIRCLE_BUILD_NUM:-} ]; then
  set_circleci_user_vernum
else
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
  USER=$(whoami)
  # avoid interp as octal!
  VERNUM=$(printf "%04d" $((10#$VERNUM)))
fi
touch $STATEDIR/$VERNUM

STACK=ecs-${USER}-${VERNUM}
KEYFORNOW=dick
if ! aws ec2 describe-key-pairs --key-names $KEYFORNOW ; then
    echo Keypair "${KEYFORNOW}" needs to be manually uploaded
fi

TEMPLATE="${wd}/dns.template"
refresh_templates $TEMPLATE
ECSCLIPATH="$GOPATH/src/github.com/aws/amazon-ecs-cli"
ECSCLIBIN="$ECSCLIPATH/bin/local/ecs-cli"
$ECSCLIBIN configure --cfn-stack-name="$STACK" --cluster "$STACK" --region $REGION
IMAGE=$(aws ec2 describe-images --owners amazon --filter="Name=name,Values=*-ecs-optimized" | jq -r '.Images[] | "\(.Name)\t\(.ImageId)"' | sort -r | head -1 | cut -f2)
grab="$(mktemp /tmp/ecs-up.XXXXXX)"
set -o pipefail
$ECSCLIBIN template --instance-type t2.medium --force --cluster "$STACK" --image-id $IMAGE --template $TEMPLATE --keypair dick --capability-iam --size 2 --disable-rollback 2>&1 | tee $grab
set +o pipefail


#INFO=$(aws cloudformation describe-stack-resources --stack-name "$STACK")
#VPC=$(echo $INFO | jq -r ' .StackResources | .[] | select(.ResourceType=="AWS::EC2::VPC") | .PhysicalResourceId ')
#SG=$(echo $INFO | jq -r ' .StackResources | .[] | select(.ResourceType=="AWS::EC2::SecurityGroup") | .PhysicalResourceId ')
# aws ec2 authorize-security-group-ingress --group-id ${SG} --protocol tcp --port 22 --cidr 0.0.0.0/0
# aws route53 create-hosted-zone --name servicediscovery.internal --hosted-zone-config Comment="Hosted Zone for ECS Service Discovery" --vpc VPCId=$VPC,VPCRegion=$REGION --caller-reference $(date +%s)

#mydir=$(mktemp -d "${TMPDIR:-/tmp/}$(basename $0).XXXXXXXXXXXX")
#zip ${mydir}/ecs-register-service-dns-lambda.zip ${wd}/ecs-register-service-dns-lambda.py

#ZONEID=$(aws route53 list-hosted-zones | jq -r '.HostedZones[] | select(.Name=="$STACK.internal." ) | .Id')
#ROLEARN=$(aws iam list-roles | jq -r '.Roles[] | select(.RoleName | contains("LambdaServiceRole")) | .Arn')

# FUNCTIONARN=$(aws lambda create-function \
#     --region $REGION \
#     --function-name registerEcsServiceDns \
#     --zip-file fileb://${mydir}/ecs-register-service-dns-lambda.zip \
#     --role $ROLEARN \
#     --environment Variables="{ZONEID=$ZONEID,CLUSTER=$STACK}" \
#     --handler ecs-register-service-dns-lambda.lambda_handler \
#     --runtime python2.7 \
#     --profile default | jq -r '.FunctionArn')
# aws events put-rule --name registerEcsServiceDnsRule --description registerEcsServiceDnsRule --event-pattern file://${wd}/cwe-ecs-rule.json
# aws events put-targets --rule registerEcsServiceDnsRule --targets "Id"="Target1","Arn"=$FUNCTIONARN

tgarns=$(aws elbv2 describe-target-groups | jq -r '.TargetGroups | map(select(.TargetGroupArn | contains("'$STACK'")) | .TargetGroupArn) | .[]')
if [ -z $tgarns ]; then
    echo ERROR Problem finding targetarns
    exit -1
fi
for tgarn in $tgarns; do
    toarr=$(aws elbv2 describe-target-health --target-group-arn $tgarn | jq -r '.TargetHealthDescriptions[] | .Target | "Id=\(.Id),Port=\(.Port)" ')
    aws elbv2 deregister-targets --target-group-arn $tgarn --targets $toarr
done
