#!/bin/bash -ex

eval `aws ecr get-login --no-include-email --region $(aws configure get region)`
rand=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)
docker-compose pull
docker-compose -p $rand --no-ansi up --no-color --abort-on-container-exit --exit-code-from fit

