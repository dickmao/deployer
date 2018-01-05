local newScrapyd(command, env) = {
  image: "303634175659.dkr.ecr.us-east-2.amazonaws.com/scrapyd-deploy:latest",
  mem_limit: 300000000,
  ports: [ "6800:6800" ],
  command: command,
  environment: env
};

{
  newScrapyd:: newScrapyd,
  version: "2",
  services: {
    base_service:: {
    },
    scrapyd_volume_mounted_service:: self["base_service"] + {
      volumes: [ "scrapyd:/var/lib/scrapyd" ],
    },
    redis: self["base_service"] + {
      image: "redis",
      mem_limit: 150000000,
      ports: [ "6379:6379" ],
      environment: [ "SERVICE_6379_NAME=_redis._tcp" ],
    },
    "redis-populate": self["base_service"] + {
      image: "303634175659.dkr.ecr.us-east-2.amazonaws.com/redis-populate:latest",
      mem_limit: 10000000,
      command: ["sh", "-c", "/wait-for-it.sh -t 500 redis:6379 -- sh -c 'cat ./redin.tmp | redis-cli -h redis --pipe --pipe-timeout 100'"],
    },
    "play-app": self["base_service"] + {
      image: "303634175659.dkr.ecr.us-east-2.amazonaws.com/play-app:0.1-SNAPSHOT",
      mem_limit: 400000000,
      ports: [ "80:9000" ],
    },
    scrapyd: self["scrapyd_volume_mounted_service"] + newScrapyd([ "scrapyd" ], []),
    "scrapyd-deploy": self["base_service"] + {
      image: "303634175659.dkr.ecr.us-east-2.amazonaws.com/scrapyd-deploy:latest",
      mem_limit: 50000000,
      command: "sh -c 'while ! curl -s http://scrapyd:6800/daemonstatus.json | grep -qw ok ; do echo Waiting daemonstatus=ok && sleep 10 ; done ; scrapyd-deploy aws'",
    },
    "scrapyd-crawl": self["scrapyd_volume_mounted_service"] + {
      image: "303634175659.dkr.ecr.us-east-2.amazonaws.com/scrapyd-deploy:latest",
      mem_limit: 50000000,
      command: "sh -c 'while ! curl -s http://scrapyd:6800/daemonstatus.json | grep -qw ok ; do echo Waiting daemonstatus=ok && sleep 10 ; done ; cron -f'",
    },
    "dedupe-on-demand": self["scrapyd_volume_mounted_service"] + {
      image: "303634175659.dkr.ecr.us-east-2.amazonaws.com/dedupe:latest",
      mem_limit: 300000000,
      command: "sh -c './wait-for-it.sh -t 500 scrapyd:6800 -- ./dedupe-on-demand.sh'",
    },
    "corenlp": self["base_service"] + {
      image: "303634175659.dkr.ecr.us-east-2.amazonaws.com/corenlp:latest",
      ports: [ "9005:9005" ],
      environment: [ "SERVICE_9005_NAME=_corenlp._tcp" ],
    },
  },
  volumes: { "scrapyd": null },
}
