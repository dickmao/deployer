#!/bin/bash -euxE

declare -A only=()
while [[ $# -gt 0 ]] ; do
  key="$1"
  case "$key" in
      -s|--service-prefix)
      only+=([$2]=1)
      shift
      shift
      ;;
      *)
      break
      ;;    
  esac
done

wd=$(dirname $0)
source ${wd}/ecs-utils.sh

eval $(getServiceConfigs)

for olddef in $(aws ecs list-task-definitions | jq -r ' .taskDefinitionArns | .[] ') ; do
    bn=$(basename $olddef)
    td=${bn%:*}
    svc=${td#*-}
    svc=${svc%%-*}
    if [ ${#only[@]} -eq 0 ] || test "${only[$svc]+isset}" ; then
        aws ecs deregister-task-definition --task-definition $olddef
    fi
done

SERVICES="services:"
for s0 in $(docker-compose config --services); do
    SERVICES=$(cat << EOF
${SERVICES}  
  $s0:
    volumes: 
      - /etc/ecs:/etc/ecs
      - /efs/var/lib/scrapyd:/var/lib/scrapyd
    env_file: ../docker-ecs.env
    dns_search: ${STACK}.internal
EOF
)
done

cat > ${STATEDIR}/docker-compose.${STACK}.yml <<EOF
version: '2'
${SERVICES}
EOF

for k in "${!hofa[@]}" ; do
    options=$(echo "${hofa[$k]}" | sed -e 's/|/ --service-configs /g')
    if [ ${#only[@]} -eq 0 ] || test "${only[$k]+isset}"; then
        ecs-cli compose -f ${wd}/docker-compose.yml -f ${STATEDIR}/docker-compose.${STACK}.yml service up$options
    fi
done
