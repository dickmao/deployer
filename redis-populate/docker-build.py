#!/usr/bin/python

from os.path import getmtime, join, realpath
import os, errno, operator, re, sys, subprocess, signal
import redis, shutil, string
from itertools import imap
from git import Repo

wdir = os.path.dirname(realpath(__file__))
try:
    shutil.rmtree(join(wdir, '.play-app'))
except OSError as e:
    if e.errno != errno.ENOENT:
        raise
play_app = Repo.clone_from("git@github.com:dickmao/play-app.git", to_path=join(wdir, '.play-app'), **{"depth": 1, "single-branch": True})

table = ['geonameid','name','asciiname','alternatenames','latitude','longitude','featureclass','featurecode','countrycode','cc2','admin1code','admin2code','admin3code','admin4code','population','elevation','dem','timezone','modificationdate']

commands = []
with open(join(wdir, ".play-app/conf/NY.tsv"), 'r') as fp:
    for line in fp:
        arr = line.rstrip('\n').split('\t')
        if arr[6] == "P":
            commands.append(["ZADD", "geoitem.index.name", "0", "{}:{}".format(arr[2].lower(), arr[2])])
            commands.append(["SADD", "georitem.{}".format(arr[2]), arr[0]])
            e = dict(zip(table[1:], arr[1:]))
            for k,v in e.iteritems():
                if arr[0] and k and v:
                    commands.append(["HSET", "geoitem.{}".format(arr[0]), k, v])
        if arr[7] == "PPLX":
            commands.append(["GEOADD", "pplx.geohash.coords", arr[5], arr[4], arr[0]])

def gen_redis_proto(*cmd):
    proto = ""
    proto += "*" + str(len(cmd)) + "\r\n"
    for arg in imap(lambda y: y, cmd):
        proto += "$" + str(len(arg)) + "\r\n"
        proto += str(arg) + "\r\n"
    return proto

redin = ''.join([gen_redis_proto(*cmd) for cmd in commands])
with open(join(wdir, "redin.tmp"), 'w+') as fp:
    fp.write("{}".format(redin))

with open(join(wdir, "Dockerfile.tmp"), 'w+') as fp:
    fp.write("""
FROM redis
MAINTAINER dick <noreply@shunyet.com>
RUN set -xe \
  && apt-get -yq update \
  && DEBIAN_FRONTEND=noninteractive apt-get -yq install curl netcat-openbsd iputils-ping vim \
  && curl -sSL https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh -o /wait-for-it.sh \
  && chmod u+x /wait-for-it.sh \
  && apt-get remove -yq curl \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*
COPY ./redin.tmp ./redin.tmp
    """)

subprocess.call(['../ecr-build-and-push.sh', './Dockerfile.tmp', 'redis-populate:latest'])
os.remove("./redin.tmp")
os.remove("./Dockerfile.tmp")
