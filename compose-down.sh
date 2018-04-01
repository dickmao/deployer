#!/bin/bash -euxE

declare -A only=()
while [[ $# -gt 0 ]] ; do
  key="$1"
  case "$key" in
      -s|--service-prefix)
      svc=$2
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
      done
  else
      exec bash -c "docker-compose -f - down <<EOF
${rendered_string}
EOF"
  fi
  exit 0
fi

printf "$rendered_string" > $STATEDIR/docker-compose.$STACK.json
eval $(getServiceConfigs)

declare -A extant
for service in $(aws ecs list-services --cluster $STACK | jq -r '.serviceArns | .[]'); do
    extant+=([-$(basename $service)]=1)
done

ECSCLIPATH="$GOPATH/src/github.com/aws/amazon-ecs-cli"
ECSCLIBIN="$ECSCLIPATH/bin/local/ecs-cli"
for k in "${!hofa[@]}" ; do
    options=$(echo "${hofa[$k]}" | sed -e 's/|/ --service-configs /g')
    svcname=$(echo "${hofa[$k]}" | sed -e 's/|/-/g')
    drop=${svcname:1}
    svcgroup=${drop%%-*}
    if [ ${#only[@]} -eq 0 ] || test "${only[$svcgroup]+isset}" ; then
        if test "${extant[$svcname]+isset}"; then
            $ECSCLIBIN compose --cluster $STACK -p '' -f ${STATEDIR}/docker-compose.${STACK}.json service down $options
        fi
    fi
done

if [ ${#only[@]} -eq 0 ] ; then
    for service in $(aws ecs list-services --cluster $STACK | jq -r '.serviceArns | .[]'); do
        aws ecs delete-service --cluster $STACK --service $service
    done
    for olddef in $(aws ecs list-task-definitions | jq -r ' .taskDefinitionArns | .[] ') ; do
        aws ecs deregister-task-definition --task-definition $olddef
    done

fi
