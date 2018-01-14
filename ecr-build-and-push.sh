#!/bin/bash -ex

DOCKERFILE=${1:-Dockerfile.tmp}
DIR=$(basename "$( cd "$( dirname "${DOCKERFILE}" )" && pwd )")
TAG=${2:-$DIR:latest}

OLDIMAGE=$(docker images -q $TAG)
docker build --file $DOCKERFILE --force-rm -t $TAG .
# not clear whether this really surgically cleans up danglers
if [ ! -z "$OLDIMAGE" ]; then
    CHILDREN=$(docker images --filter "since=${OLDIMAGE}" --filter "before=$TAG" --quiet)
    if [ ! -z $CHILDREN ] && ! docker inspect --format='{{.Id}} {{.Parent}}' $CHILDREN | grep $OLDIMAGE ; then
        docker rmi -f $OLDIMAGE
    fi
fi

if [ -z $(aws configure get region) ]; then
    aws configure set region us-east-2
fi
eval `aws ecr get-login --no-include-email`
if ! aws ecr describe-repositories --repository-names ${TAG%:*} 2>/dev/null ; then
    aws ecr create-repository --repository-name  ${TAG%:*}
fi
docker tag $TAG 303634175659.dkr.ecr.us-east-2.amazonaws.com/$TAG
docker push 303634175659.dkr.ecr.us-east-2.amazonaws.com/$TAG


