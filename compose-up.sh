#!/bin/bash -euxE

declare -A only=()
declare -A except=()
while [[ $# -gt 0 ]] ; do
  key="$1"
  case "$key" in
      -x|--except-service-prefix)
      svc=$2
      except+=([$svc]=1)
      shift
      shift
      ;;
      -s|--service-prefix)
      svc=$2
      only+=([$svc]=1)
      shift
      shift
      ;;
      -d|--debug)
      debug=" --debug"
      shift
      ;;
      -m|--mode)
      mode=$2
      shift
      shift
      ;;
      *)
      break
      ;;    
  esac
done

debug=${debug:-}
mode=${mode:-dev}
wd=$(dirname $0)
if [ $mode == "dev" ]; then
  source ${wd}/ecs-utils.sh 0
else
  source ${wd}/ecs-utils.sh
fi
rendered_string=$(render_string $mode)
if [ $mode == "dev" ]; then
    if [ ${#except[@]} -ne 0 ] ; then
        echo "-x is not supported in dev mode"
        exit 2
    fi

    if [ ${#only[@]} -ne 0 ] ; then
        for s in "${!only[@]}"; do
            # I have issues with volume mounts with --force-recreate (scrapyd-seed)
            docker-compose -f - rm --stop --force $s<<EOF
${rendered_string}
EOF
            docker-compose -f - up -d --no-deps $s<<EOF
${rendered_string}
EOF
        done
        exit 0
    else
        exec bash -c "docker-compose -f - up -d <<EOF
${rendered_string}
EOF"
    fi
fi

printf "$rendered_string" > $STATEDIR/docker-compose.$STACK.json

eval $(getServiceConfigs)

# for olddef in $(aws ecs list-task-definitions | jq -r ' .taskDefinitionArns | .[] ') ; do
#     bn=$(basename $olddef)
#     td=${bn%:*}
#     svc=${td#*-}
#     svc=${svc%%-*}
#     if [ ${#only[@]} -eq 0 ] || test "${only[$svc]+isset}" ; then
#         aws ecs deregister-task-definition --task-definition $olddef
#     fi
#done

ECSCLIPATH="$GOPATH/src/github.com/aws/amazon-ecs-cli"
ECSCLIBIN="$ECSCLIPATH/bin/local/ecs-cli"
order_matters=("${!hofa[@]}")
IFS=$'\n' order_matters=($(sort <<<"${order_matters[*]}"))
unset IFS
# order should not matter but RegisterEcsServiceDns not getting CreateService from scrapyd going first
for k in "${order_matters[@]}" ; do
    options=$(echo "${hofa[$k]}" | sed -e 's/|/ --service-configs /g')

    # currently only handle single port (other possibilities include ranges 9001-9005)
    elb=""
    PORTS=$(cat $STATEDIR/docker-compose.$STACK.json | jq -r ".services | .$k | select(has(\"ports\")) | .ports[]")
    if [[ $PORTS =~ ^[[:digit:]]+$ ]]; then
        # query target group arn for listener on that port
        targetarn=$(aws elbv2 describe-target-groups | jq -r '.TargetGroups[] | select(.Port=='$PORTS') | select(.TargetGroupArn | contains("'$STACK'")) | .TargetGroupArn')
        if [ -z $targetarn ]; then
          echo ERROR Problem finding targetarn
          exit -1
        fi

        # targetarn=$(aws elbv2 describe-target-groups | jq -r '.TargetGroups[] | select(.Tags[] | select(.Key=="LoadBalancerPort" and .Value=="'$PORTS'") | select(.TargetGroupArn | contains("'$STACK'")) | .TargetGroupArn')

        # targetarn=$(aws cloudformation describe-stack-resources --stack-name ecs-dick-0001|jq -r '.StackResources[] | select(.ResourceType=="AWS::ElasticLoadBalancingV2::TargetGroup") | .PhysicalResourceId')
        # service specifies desired count of tasks which are composed of container-names
        ECSROLE=$(aws iam list-roles | jq -r '.Roles[] | select(.RoleName | contains("ECSRole")) | .RoleName')
        elb=" --target-group-arn $targetarn --container-name $k --container-port $PORTS --role $ECSROLE"
    fi
    if ( [ ${#only[@]} -ne 0 ] && test "${only[$k]+isset}" ) || 
       ( [ ${#except[@]} -ne 0 ] && ! test "${except[$k]+isset}" ) ||
       ( [ ${#only[@]} -eq 0 ] && [ ${#except[@]} -eq 0 ] ) ; then
        $ECSCLIBIN compose$debug --cluster $STACK --ecs-params $wd/ecs-params.yml -p '' -f $STATEDIR/docker-compose.$STACK.json service up$elb$options --deployment-max-percent 200 --deployment-min-healthy-percent 50 --timeout 5
    fi
done
#for arn in $(aws elbv2 describe-load-balancers | jq -r '.LoadBalancers[] | .LoadBalancerArn') ; do 
#    port=$(aws elbv2   describe-listeners --load-balancer-arn $arn | jq -r '.Listeners[] | .Port')
#    if [ $port == $PORTS ] ; then 
