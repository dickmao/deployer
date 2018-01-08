#!/bin/bash -ex

cd $(dirname $0)

if [ ! -z $(docker ps -aq --filter "name=scrapyd-seed") ]; then
  docker rm -f $(docker ps -aq --filter "name=scrapyd-seed")
fi

cat > ./Dockerfile.tmp <<EOF
FROM cgswong/aws:s3cmd
MAINTAINER dick <noreply@shunyet.com>
COPY ./seed.sh /
ENTRYPOINT /seed.sh
EOF

../ecr-build-and-push.sh ./Dockerfile.tmp scrapyd-seed:latest

rm ./Dockerfile.tmp
