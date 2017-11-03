#!/bin/bash -ex

DOCKERFILE=${1:-Dockerfile.tmp}
DIR=$(basename "$( cd "$( dirname "${DOCKERFILE}" )" && pwd )")
TAG=${2:-$DIR:latest}



OLDIMAGE=$(docker images -q $TAG)
if [ ! -z "$OLDIMAGE" ]; then
    CHILDREN=$(docker images --filter "since=${OLDIMAGE}" --quiet)
    if [ -z $CHILDREN ] || [ ! docker inspect --format='{{.Id}} {{.Parent}}' $CHILDREN | grep $OLDIMAGE ] ; then
        docker rmi -f $OLDIMAGE
    fi
fi
docker build --file $DOCKERFILE --force-rm -t $TAG .
eval `aws ecr get-login --no-include-email`
if ! aws ecr describe-repositories --repository-names ${TAG%:*} 2>/dev/null ; then
    aws ecr create-repository --repository-name  ${TAG%:*}
fi
docker tag $TAG 303634175659.dkr.ecr.us-east-2.amazonaws.com/$TAG
docker push 303634175659.dkr.ecr.us-east-2.amazonaws.com/$TAG


