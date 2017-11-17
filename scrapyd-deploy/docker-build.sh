#!/bin/bash -ex

from_scrapyd_deploy=$(docker images -q scrapyd-deploy:scaff)
from_scrapyd_deploy=${from_scrapyd_deploy:-vimagick/scrapyd}
while [[ $# -gt 0 ]] ; do
  key="$1"
  case "$key" in
      -s|--scratch)
      scratch=1
      from_scrapyd_deploy="vimagick/scrapyd"
      shift
      ;;
      *)
      break
      ;;    
  esac
done

cd $(dirname $0)
if [ -d ".scrapy" ]; then
  (cd .scrapy ; git pull )  
else
  git clone -b redis --depth=1 --single-branch git@github.com:dickmao/cl-housing-cars.git .scrapy
fi

if [ ! -z $(docker ps -aq --filter "name=scrapyd") ]; then
  docker rm -f $(docker ps -aq --filter "name=scrapyd")
fi

COPY=""
for file in $( cd .scrapy ; git ls-files ) ; do
  dir=$(dirname $file)
  COPY=$(printf "$COPY\nCOPY .scrapy/${file} /${dir}/")
done

cat > ./bash_aliases.tmp <<EOF
function schedule {
  SPIDER=\${1:-que}
  OUTPUT=\$(curl -s http://scrapyd:6800/listjobs.json?project=tutorial | jq -r '.status, .running[].spider, .pending[].spider')
  if [ "ok" != \${OUTPUT%%\$'\n'*} ]; then
    (>&2 echo "scrapyd status \${OUTPUT%%\$'\n'*}")
    return 1
  fi
  read -r -a array <<< \${OUTPUT#*\$'\n'}
  if [[ " \${array[@]} " =~ " \$SPIDER " ]]; then
    (>&2 echo "\$SPIDER running or pending")
    return 1
  fi
  scrapyd-client -t http://scrapyd:6800 schedule -p tutorial \$SPIDER
}

alias listspiders='curl http://scrapyd:6800/listspiders.json?project=tutorial'
alias listjobs='curl http://scrapyd:6800/listjobs.json?project=tutorial'
EOF

cat > ./scrapyd.conf.tmp <<EOF
[scrapyd]
eggs_dir          = /var/lib/scrapyd/eggs
logs_dir          = /var/lib/scrapyd/logs
dbs_dir           = /var/lib/scrapyd/dbs
jobs_to_keep      = 5
max_proc          = 0
max_proc_per_cpu  = 4
finished_to_keep  = 100
poll_interval     = 5
bind_address      = 0.0.0.0
http_port         = 6800
debug             = off
runner            = scrapyd.runner
application       = scrapyd.app.application
launcher          = scrapyd.launcher.Launcher

[services]
schedule.json     = scrapyd.webservice.Schedule
cancel.json       = scrapyd.webservice.Cancel
addversion.json   = scrapyd.webservice.AddVersion
listprojects.json = scrapyd.webservice.ListProjects
listversions.json = scrapyd.webservice.ListVersions
listspiders.json  = scrapyd.webservice.ListSpiders
delproject.json   = scrapyd.webservice.DeleteProject
delversion.json   = scrapyd.webservice.DeleteVersion
listjobs.json     = scrapyd.webservice.ListJobs
daemonstatus.json = scrapyd.webservice.DaemonStatus
EOF

cat > ./scrapyd-schedule.tmp <<EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# m h dom mon dow user   command
10   *   *   *   * root   bash -lc 'schedule que' '> /proc/1/fd/1 2>/proc/1/fd/2'
25   *   *   *   * root   bash -lc 'schedule dmoz' '> /proc/1/fd/1 2>/proc/1/fd/2'
EOF

from=${scratch:-vimagick/scrapyd}
cat > ./Dockerfile.tmp <<EOF
FROM ${from_scrapyd_deploy}
MAINTAINER dick <noreply@shunyet.com>
RUN set -xe \
  && apt-get -yq update \
  && DEBIAN_FRONTEND=noninteractive apt-get -yq install gcc python-dev libenchant1c2a cron jq netcat-openbsd \
  && apt-get clean \
  && curl -sSL https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh -o ./wait-for-it.sh \
  && chmod u+x ./wait-for-it.sh \
  && pip install pytz python-dateutil redis pyenchant nltk gensim \
  && python -m nltk.downloader punkt \
  && echo "source /root/.bash_aliases" >> /root/.bashrc \
  && rm -rf /var/lib/apt/lists/*
COPY ./scrapyd-schedule.tmp /etc/cron.d/scrapyd-schedule
RUN chmod 0644 /etc/cron.d/scrapyd-schedule
$COPY
COPY ./scrapyd.conf.tmp /etc/scrapyd/scrapyd.conf
COPY ./bash_aliases.tmp /root/.bash_aliases
EOF

../ecr-build-and-push.sh ./Dockerfile.tmp scrapyd-deploy:latest

rm ./Dockerfile.tmp
rm ./scrapyd.conf.tmp
rm ./scrapyd-schedule.tmp
rm ./bash_aliases.tmp

if [ ! -z $scratch ] ; then
  SCAFF=$(docker images -q scrapyd-deploy:scaff)
  if [ ! -z $SCAFF ]; then
    SCAFF_PARENT=$(docker inspect --format='{{.Parent}}' $SCAFF | cut -d':' -f2)
    docker rmi -f $SCAFF
    if [ ! -z $SCAFF_PARENT ]; then
      docker rmi -f ${SCAFF_PARENT}
    fi  
  fi
fi

if [ -z $(docker images -q scrapyd-deploy:scaff) ] ; then
  RAND=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
  docker run --name=$RAND scrapyd-deploy:latest true
  TOCOMMIT=$(docker ps -aq --filter="name=$RAND")
  docker commit -m "need faster" $TOCOMMIT scrapyd-deploy:scaff
  docker rm $TOCOMMIT
fi
