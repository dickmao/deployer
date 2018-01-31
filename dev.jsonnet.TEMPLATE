local repository = "";
local aws_env = [
  "AWS_DEFAULT_REGION=" + std.extVar("AWS_DEFAULT_REGION"),
  "AWS_ACCESS_KEY_ID=" + std.extVar("AWS_ACCESS_KEY_ID"),
  "AWS_SECRET_ACCESS_KEY=" + std.extVar("AWS_SECRET_ACCESS_KEY"),
  "GIT_USER=" + std.extVar("GIT_USER"),
  "GIT_PASSWORD=" + std.extVar("GIT_PASSWORD")  
];

local newScrapyd(command, env) = {
  image: repository + "scrapyd-deploy:latest",
  mem_limit: "300m",
  ports: [ "6800:6800" ],
  command: command,
  environment: aws_env + env
};

{
  newScrapyd:: newScrapyd,
  aws_env:: aws_env,
  version: "2",
  services: {
    base_service:: {
    },
    scrapyd_volume_mounted_service:: self["base_service"] + {
      volumes: [ "scrapyd:/var/lib/scrapyd" ],
    },
    redis: self["base_service"] + {
      image: repository + "redis",
      mem_limit: "150m",
      ports: [ "6379:6379" ],
      environment: [ "SERVICE_6379_NAME=_redis._tcp" ],
    },
    "redis-populate": self["base_service"] + {
      image: repository + "redis-populate:latest",
      mem_limit: "50m",
      command: ["sh", "-c", "/wait-for-it.sh -t 500 redis:6379 -- sh -c 'cat ./redin.tmp | redis-cli -h redis --pipe --pipe-timeout 100'"],
    },
    "redis-depopulate": self["base_service"] + {
      image: repository + "redis-populate:latest",
      mem_limit: "50m",
      command: ["sh", "-c", "/wait-for-it.sh -t 500 redis:6379 -- sh -c 'cat ./redin.tmp | redis-cli -h redis --pipe --pipe-timeout 100'"],
    },
    "play-app": self["base_service"] + {
      image: repository + "play-app:0.1-SNAPSHOT",
      mem_limit: "512m",
      ports: [ "80:9000" ],
    },
    "scrapyd": self["scrapyd_volume_mounted_service"] + newScrapyd([ "scrapyd" ], []),
    "scrapyd-seed": self["scrapyd_volume_mounted_service"] + {
      image: repository + "scrapyd-seed:latest",
      environment: aws_env
    },
    "scrapyd-deploy": self["base_service"] + {
      image: repository + "scrapyd-deploy:latest",
      mem_limit: "50m",
      command: "sh -c 'while ! curl -s http://scrapyd:6800/daemonstatus.json | grep -qw ok ; do echo Waiting daemonstatus=ok && sleep 10 ; done ; scrapyd-deploy aws'",
    },
    "scrapyd-crawl": self["scrapyd_volume_mounted_service"] + {
      image: repository + "scrapyd-deploy:latest",
      mem_limit: "50m",
      command: "sh -c 'while ! curl -s http://scrapyd:6800/daemonstatus.json | grep -qw ok ; do echo Waiting daemonstatus=ok && sleep 10 ; done ; cron -f'",
    },
    "dedupe-on-demand": self["scrapyd_volume_mounted_service"] + {
      image: repository + "dedupe:latest",
      mem_reservation: "512m",
      command: "sh -c './wait-for-it.sh -t 500 scrapyd:6800 -- ./dedupe-on-demand.sh'",
      environment: aws_env
    },
    "corenlp": self["base_service"] + {
      image: repository + "corenlp:latest",
      mem_reservation: "512m",
      ports: [ "9005:9005" ],
      environment: [ "SERVICE_9005_NAME=_corenlp._tcp" ],
    },
  },
  volumes: { "scrapyd": null },
}
