#!/bin/bash -euxE

declare -A only=()
while [[ $# -gt 0 ]] ; do
  key="$1"
  case "$key" in
      -s|--service-prefix)
      svc=${2%%-*}
      only+=([$svc]=1)
      shift
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

mode=${mode:-dev}
wd=$(dirname $0)
if [ $mode == "dev" ]; then
  source ${wd}/ecs-utils.sh 0
else
  source ${wd}/ecs-utils.sh
fi
rendered_string=$(render_string $mode)
if [ $mode == "dev" ]; then
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
        exec bash -c "docker-compose -f - up<<EOF
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
for k in "${!hofa[@]}" ; do
    options=$(echo "${hofa[$k]}" | sed -e 's/|/ --service-configs /g')
    if [ ${#only[@]} -eq 0 ] || test "${only[$k]+isset}"; then
        $ECSCLIBIN compose --cluster $STACK --ecs-params $wd/ecs-params.yml -p '' -f $STATEDIR/docker-compose.$STACK.json service up$options --deployment-max-percent 100 --deployment-min-healthy-percent 0 --timeout 5
    fi
done
