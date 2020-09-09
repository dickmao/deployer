declare -A clustersvc2ip
clustersvc2ip["0000:"]="localhost"

function failed {
  local project
  project=$(basename $(pwd))
  local buildnum
  local step
  local token
  token=$(cat ~/aws/circleci.api)
  buildnum=${1:-$(curl -sku $token: https://circleci.com/api/v1.1/project/github/dickmao/$project?filter=failed | jq -r '.[0] | .build_num')}
  local explicit_step
  explicit=${2:-}
  if [ -z $explicit ] ; then
    step=$(curl -sku $token: https://circleci.com/api/v1.1/project/github/dickmao/$project/$buildnum | jq -r '.steps[] | select(.actions | select( .[] | .failed==true)) | .actions[] | .output_url' )
    if [ -z $step ]; then
      step=$(curl -sku $token: https://circleci.com/api/v1.1/project/github/dickmao/$project/$buildnum | jq -r '.steps[-1] | .actions[] | .output_url' )
    fi
  else
      step=$(curl -sku $token: https://circleci.com/api/v1.1/project/github/dickmao/$project/$buildnum | jq -r ".steps[$explicit] | .actions[] | .output_url" )
  fi
  curl -s $step | gzip -dc| jq -r '.[] | .message' | dos2unix
}

function exevents {
  local log
  local json
  local stackid
  local substackid
  log=$(find /tmp/ecs-up.?????? -exec ls -rdt {} + | tail -1)
  # afh superuser.com eval makes the for-split quotation-aware
  json=$(aws cloudformation describe-stack-events  --stack-name $(eval 'for word in '$(tac $log | grep -m 1 level=error )'; do if [ ${word%%=*} == "resource" ] ; then echo ${word#*=}; fi ; done ' ))
  stackid=$(echo $json | jq -r '.StackEvents[] | select(.ResourceStatus=="CREATE_FAILED") | select(.ResourceStatusReason | contains("Embedded stack")) | .ResourceStatusReason' | cut -d' ' -f3)
  if [ ! -z $stackid ]; then
    while [ 1 ] ; do
      json=$(aws cloudformation describe-stack-events  --stack-name $stackid)
      substackid=$(echo $json | jq -r '.StackEvents[] | select(.ResourceStatus=="CREATE_FAILED") | .StackId' | tail -1)
      if [ -z $substackid ]; then
        break
      else
        stackid=$substackid
        substackid=$(echo $json | jq -r '.StackEvents[] | select(.ResourceStatus=="CREATE_FAILED") | select(.ResourceStatusReason | contains("Embedded stack")) | .ResourceStatusReason' | tail -1 | cut -d' ' -f3)
        if [ -z $substackid ]; then
          break
        fi
        stackid=$substackid
      fi
    done
  fi
  echo $json | jq -r '.StackEvents[] | select(.ResourceStatus=="CREATE_FAILED") | .ResourceStatusReason' | tail -1
}

function lambdalogs {
  local farback
  local loggroups
  local choice
  farback=${1:--1h}
  choice=${2:-}
  read -r -a loggroups <<< $(awslogs groups)
  if [ -z $choice ]; then
    local i
    i=1
    for lg in ${loggroups[@]}; do
      echo $i $lg
      ((i++))
    done
    read -p "Choose: " choice
  fi
  ((choice--))
  awslogs get ${loggroups[$choice]} -s$farback --no-group --no-stream | perl -ne 'use POSIX "strftime"; use Date::Parse; my $line =$_; if ($line =~ /eventtime/i) { $line =~ /:\s+"([^"]+)"/; my $capture = $1; my $time = str2time($capture); my $conv = strftime("%FT%H:%M:%S\n", localtime $time); chomp $conv; $line =~ s/$capture/$conv/e; } print $line;'
}

function cloudtrails {
  farback=${1:-20 minutes ago}
  vernum=$(get-vernum ${2:-})
  id=$(aws cloudformation describe-stack-resources --stack-name $(get-cluster $vernum) | jq -r '.StackResources[] | select(.ResourceType=="AWS::S3::Bucket") | .PhysicalResourceId '  )
  rm -rf ~/.trailscraper/*
  TZ=US/Eastern trailscraper download --bucket  $id  --region us-east-2 --region us-east-1 --from "'$farback'" --to "now" --account-id 303634175659
  skan ~/.trailscraper | awk {'print $4'} | xargs zcat | jq -r '.Records[]' | perl -ne 'use POSIX "strftime"; use Date::Parse; my $line =$_; if ($line =~ /eventtime/i) { $line =~ /:\s+"([^"]+)"/; my $capture = $1; my $time = str2time($capture); my $conv = strftime("%FT%H:%M:%S\n", localtime $time); chomp $conv; $line =~ s/$capture/$conv/e; } print $line;'
}

function myip() {
  dig +short myip.opendns.com @resolver1.opendns.com
}

alias findtext='find -L . -path ./.cos -prune -false -o -type f -exec grep -Iq . {} \; -and -print 2>&1 | xargs egrep -n '
function circleci() {
  declare -A aa
  IFS=$'\n'
  for kv in $(cat <<EOF | git credential fill
protocol=https
host=github.com
EOF
  ); do
    k="${kv%=*}"
    v="${kv#*=}"
    aa+=([$k]="$v")
  done
  GIT_USER="${aa['username']}"
  GIT_PASSWORD="${aa['password']}"
  if [ ! -z ${1:-} ] && [ ${1:-} == 'build' ]; then
    $(which circleci) $* -e AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id) -e AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key) -e AWS_REGION=$(aws configure get region) -e AWS_DEFAULT_REGION=$(aws configure get region) -e GIT_USER=${GIT_USER} -e GIT_PASSWORD=${GIT_PASSWORD}
  else
    $(which circleci) $*
  fi
}
alias gradle='gradle -console plain'
alias findfiles='find -L . -path ./.cos -prune -false -o -type f 2>&1| egrep '
alias pycheck='python -m py_compile '
alias danglers='docker rmi $(docker images --quiet --filter "dangling=true")'
alias dos="tr -d '\015' <"
alias pricing="curl -s http://localhost:8080/ec2/regions/us-east-2 | jq -r '.[] | select(.price < 0.40) | [.type , .price ] '"
alias drown="nohup play -n synth brownnoise synth pinknoise mix synth sine amod 0.17 85 >/dev/null 2>/dev/null &"
alias killdrown="ps -ef|grep -w brownnoise | awk '{print \$2}' | xargs kill"
function whatis() {
    cat $1 | shyaml get-value $2
}
alias gitout="git log --graph --oneline --all --decorate"
alias killcorenlp="wget localhost:9005/shutdown?key=\$(cat /var/tmp/corenlp.shutdown) -O -"
# git config --global alias.conflicts "diff --name-only --diff-filter=U"

# export SBT_OPTS="-Xmx4g"
# export DOCKER_HOST_IP=$(ifconfig docker0 | grep -w inet | awk '{print $2}')
stty ixon

if [ -z ${AWS_ACCESS_KEY_ID:-} ] && aws configure --profile default list 2>&1 >/dev/null ; then
  export AWS_DEFAULT_PROFILE=default
  export AWS_PROFILE=${AWS_DEFAULT_PROFILE}
fi

function ssh-mongo {
    local vernum
    vernum=$(get-vernum ${1:-});
    if test "${clustersvc2ip[${vernum}:mongo]+isset}" && ! q_cluster_changed $vernum 0 ; then
      VERNUM=$vernum ssh-ecs 0 ssh ${clustersvc2ip["${vernum}:mongo"]}
      return
    fi
    VERNUM=$vernum scp-ecs $HOME/.ssh/id_rsa .ssh/
    local mongo
    mongo=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=PrimaryReplicaNode0" | jq -r ".Reservations[] | select(.Instances[] | select(.State.Code==16))| .Instances[-1] | select(.Tags[] | select(.Key==\"aws:cloudformation:stack-name\") | select(.Value | contains(\"-${vernum}\"))) | .PrivateIpAddress ")
    clustersvc2ip["${vernum}:mongo"]=$mongo
    VERNUM=$vernum ssh-ecs 0 ssh ${clustersvc2ip["${vernum}:mongo"]}
}

function wrap-ssh-my() {
    local clusterkey
    clusterkey=$1
    shift
    ip=$1
    # parent variables like clustersvc2ip don't get updated in subshells
    clustersvc2ip["$clusterkey"]=$ip
    ssh-my "$@"
}

function ssh-my() {
    ssh -x -o LogLevel=QUIET -o StrictHostKeyChecking=no -t ec2-user@$*
}

function export_from_config() {
  export $1=$(perl -e "my \$xml = do{local(@ARGV,$/)='$HOME/.aws/credentials';<>}; my \$regex = \"\L$1\"; \$xml =~ /\$regex\s*=\s*(\S+)/; print \$1;")
}

function aws_configure() {
  export_from_config "AWS_ACCESS_KEY_ID"
  export_from_config "AWS_SECRET_ACCESS_KEY"
  export PATH=/opt/terraform:$PATH
}

# alias sbt="$(which sbt) -mem 4000 -jvm-debug 9997"
# alias domino_nucleus="$(which sbt) -mem 4000 -jvm-debug 9998 -shell 'project nucleus' compile run"
# alias domino_executor="$(which sbt) -mem 4000 -jvm-debug 9999 -shell 'project executor' compile run"
function t() {
    if [ -z $1 ] ; then
      date +%s
    else
      date -d @$1
    fi
}

alias alicia='ssh -o StrictHostKeyChecking=no -i ~/aws/alicia.pem -X ubuntu@54.218.82.194'
function cpalicia {
  rsync -avzSHe "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /home/dick/aws/alicia.pem" $1 ubuntu@54.218.82.194:scrapy/
}
function aliciacp {
  rsync -avzSHe "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /home/dick/aws/alicia.pem" ubuntu@54.218.82.194:$1 $2
}

function mems {
  ps -eo size,pid,user,command --sort -size | awk '{ hr=$1/1024 ; printf("%13.2f Mb ",hr) } { for ( x=4 ; x<=NF ; x++ ) { printf("%s ",$x) } print "" }'
}

function docke {
  docker exec -ti $(docker ps -q --filter "label=com.docker.compose.service=$1" | head -1) bash
}
function dockl {
  tail=
  if [ $1 == '-f' ]; then
    shift
    tail=" -f"
  fi
  docker logs${tail} $(docker ps -qla --filter "label=com.docker.compose.service=$1" | head -1) 2>&1
}
function dockr {
  docker rm -f $(docker ps -aq --filter "label=com.docker.compose.service=$1" | head -1)
}
function dockrm {
  docker ps -a | cut -d' ' -f1 | grep -v CONTAINER | xargs docker rm
}
function dockc {
  docker inspect --format='{{.Id}} {{.Parent}}' $(docker images --filter since=$1 --quiet)
}

function get-cluster {
  if [ ! -z "${ECS_CLUSTER:-}" ]; then
    echo "$ECS_CLUSTER"
  else
    local vernum
    vernum=$(get-vernum ${1:-})
    local whoiam
    whoiam="${ECS_WHOAMI:-$(whoami)}"
    echo ecs-${whoiam}-${vernum}
  fi
}

function get-vernum {
  local vernum
  vernum=${1:-}
  if [ -z $vernum ]; then
    if [ ! -z ${ECS_CLUSTER:-} ]; then
      vernum=${ECS_CLUSTER##*-}
    elif [ ! -z ${VERNUM:-} ]; then
      vernum=$VERNUM
    else
      vernum=$(cd $(dirname ${BASH_SOURCE})/ecs-state ; ls -1 [a-z0-9][a-z0-9][a-z0-9][a-z0-9] 2>/dev/null| tail -1 | cut -d ' ' -f1)
    fi
  fi
  echo $vernum
}

function rsync-from-ecs {
  src=${1:-}
  dest=${2:-}
  vernum=$(get-vernum ${3:-})
  rsync -vaze "ssh -i ~/.ssh/id_rsa" ec2-user@$(aws ec2 describe-instances --instance-ids $(aws ecs describe-container-instances --cluster $(get-cluster $vernum) --container-instances $(aws ecs list-container-instances --cluster $(get-cluster $vernum) | jq -r '.[] | .[]') | jq -r ".containerInstances[$which] | .ec2InstanceId ") --query "Reservations[*].Instances[*].PublicIpAddress" --output text):$src $dest
}

function scp-ecs {
  src=${1:-}
  dest=${2:-}
  vernum=$(get-vernum ${3:-})
  howmany=$(aws ecs list-container-instances --cluster $(get-cluster $vernum) | jq -r '.[] | .[]' | wc -l)
  howmany=$(($howmany-1))
  for which in `seq 0 $howmany`; do
    scp -i ~/.ssh/id_rsa $src ec2-user@$(aws ec2 describe-instances --instance-ids $(aws ecs describe-container-instances --cluster $(get-cluster $vernum) --container-instances $(aws ecs list-container-instances --cluster $(get-cluster $vernum) | jq -r '.[] | .[]') | jq -r ".containerInstances[$which] | .ec2InstanceId ") --query "Reservations[*].Instances[*].PublicIpAddress" --output text):$dest
  done
}

function awslog {
  local which=${2:-1}
  aws logs get-log-events --log-group-name "/aws/batch/job" --log-stream-name $(aws logs describe-log-streams --log-group-name "/aws/batch/job" --descending --order-by LastEventTime --max-items 10 | jq -r ' .logStreams[] | .logStreamName ' | grep $1 | head -$which | tac | head -1 ) --no-start-from-head | jq -r ' .events | .[].message '
}
function awslog2 {
  group_name='/aws/batch/job'
  stream_name=$(aws logs describe-log-streams --log-group-name ${group_name} --descending --order-by LastEventTime --max-items 1  | jq -r ' .logStreams[0] | .logStreamName ')
  start_seconds_ago=300

  start_time=$(( ( $(date -u +"%s") - $start_seconds_ago ) * 1000 ))
  while [[ -n "$start_time" ]]; do
    loglines=$( aws --output text logs get-log-events --log-group-name "$group_name" --log-stream-name "$stream_name" --start-time $start_time )
    [ $? -ne 0 ] && break
    next_start_time=$( sed -nE 's/^EVENTS.([[:digit:]]+).+$/\1/ p' <<< "$loglines" | tail -n1 )
    [ -n "$next_start_time" ] && start_time=$(( $next_start_time + 1 ))
    echo "$loglines"
    sleep 15
  done
}

function unset_clustersvc2ip {
  local vernum
  local svc
  svc=${1:-}
  vernum=$(get-vernum ${2:-})
  sgroup=${svc%%-*}

  for k in "${!clustersvc2ip[@]}" ; do
    K=${k##*:}
    if [ "x${K%%-*}" == "x$sgroup" ]; then
      echo deleting $k
      unset clustersvc2ip["$k"]
    fi
  done
}

function q_cluster_changed {
  local vernum
  local idx
  vernum=$(get-vernum ${1:-})
  idx=${2:-}
  if test "${clustersvc2ip[${vernum}:${idx}]+isset}" ; then
    if ! nc -zw 1 ${clustersvc2ip["${vernum}:${idx}"]} 22 ; then
      unset clustersvc2ip["${vernum}:${idx}"]
      return 0
    else
      return 1
    fi
  fi
  return 0
}

function get-ip-for-index {
  local svc
  local vernum
  svc="${1:-}"
  vernum=$(get-vernum ${2:-})
  if ! q_cluster_changed $vernum $svc ; then
    echo ${clustersvc2ip["${vernum}:${svc}"]}
    return
  fi
  local instances
  instances=$(aws ecs list-container-instances --cluster $(get-cluster $vernum) 2>/dev/null | jq -r '.[] | .[] ' 2>/dev/null)
  if [ ! -z "$instances" ] ; then
    ip=$(aws ec2 describe-instances --instance-ids $(aws ecs describe-container-instances --cluster $(get-cluster $vernum) --container-instances $instances | jq -r ".containerInstances[$svc] | .ec2InstanceId ") --query "Reservations[*].Instances[*].PublicIpAddress" --output text)
    clustersvc2ip["${vernum}:${svc}"]=$ip
    echo $ip
  fi
}


function get-ip-for-svc {
  svc="${1:-}"
  sgroup=${svc%%-*}
  vernum=$(get-vernum ${2:-})
  if ! q_cluster_changed $vernum $svc ; then
    echo ${clustersvc2ip["${vernum}:${svc}"]}
    return
  fi

  for arn in $(aws ecs list-tasks --cluster $(get-cluster $vernum) | jq -r '.taskArns[] ') ; do
    group_inst=$(aws ecs describe-tasks --cluster $(get-cluster $vernum) --tasks $arn | jq -r '.tasks[] | "\(.group) \(.containerInstanceArn)" ')
    group=${group_inst%% *}
    group=${group##*:}
    group=${group%%-*}
    inst=${group_inst##* }
    if [ $group == $sgroup ] ; then
      ec2=$(aws ecs describe-container-instances --cluster $(get-cluster $vernum) --container-instances $inst | jq -r '.containerInstances[] | .ec2InstanceId')
      ip=$(aws ec2 describe-instances --instance-ids $ec2 --query "Reservations[*].Instances[*].PublicIpAddress" --output text)
      clustersvc2ip["${vernum}:${svc}"]=$ip
      echo $ip
      break
    fi
  done
}

function dockl-ecs {
  tail=""
  if [ $1 == "-f" ]; then
    shift
    tail=" -f"
  fi
  svc="$1"
  vernum=$(get-vernum ${2:-})
  ip=$(get-ip-for-svc $svc $vernum)
  if [ ! -z $ip ]; then
    wrap-ssh-my "$vernum:$svc" $ip dockl$tail $svc
  fi
}

function docke-ecs {
  svc="$1"
  shift
  cmd="$@"
  ip=$(get-ip-for-svc $svc)
  if [ ! -z $ip ]; then
    local vernum
    vernum=$(get-vernum)
    wrap-ssh-my "$vernum:$svc" $ip docke $svc $cmd
  else
    return 1
  fi
}

function dockr-ecs {
  svc="$1"
  vernum=$(get-vernum ${2:-})
  ip=$(get-ip-for-svc $svc $vernum)
  if [ ! -z $ip ]; then
    wrap-ssh-my "$vernum:$svc" $ip dockr $svc
  else
    return 1
  fi
}

function ssh-ecs {
  svc="$1"
  shift
  cmd="$@"
  vernum=$(get-vernum)
  re='^[0-9]+$' # yes, i have to assign it first.  See SO Charles Duffy
  local ip
  ip=""
  if [[ $svc =~ $re ]]; then
    ip=$(get-ip-for-index $svc $vernum)
  else
    ip=$(get-ip-for-svc $svc $vernum)
  fi
  if [ -z $ip ]; then
    echo what is $vernum
  else
    wrap-ssh-my "$vernum:$svc" $ip $cmd
  fi
}

function read-data {
  while IFS= read -r line ; do jsonlint <(echo "$line") ; done < "$1"
}

function grab-lgi {
  foo=$(s3cmd ls s3://303634175659.lgi/Data.* | sort | tail -1 | awk '{print $NF}') ; if [ ! -e $(basename $foo) ] ; then s3cmd get --quiet --force $foo ; fi ; read-data $(basename $foo)
}
