local devJsonnetTemplate = import "./dev.jsonnet.TEMPLATE";
local repository="303634175659.dkr.ecr.us-east-2.amazonaws.com/";
devJsonnetTemplate.composeUp(repository=repository) + {
  services+: {
    base_service:: {
      dns_search: std.extVar("cluster") + ".internal",
    },
    scrapyd_volume_mounted_service: self["base_service"] + {
      volumes: [ "/efs/var/lib/scrapyd:/var/lib/scrapyd" ],
    },
    redis_volume_mounted_service: self["base_service"] + {
      volumes: [ "/efs/var/lib/redis:/data" ],
    },
    mongo_volume_mounted_service: self["base_service"] + {
      volumes: [ "/efs/var/lib/mongodb:/var/lib/mongodb" ],
    },
    redis: self["redis_volume_mounted_service"] + devJsonnetTemplate.newRedis(repository, [ "SERVICE_6379_NAME=_redis._tcp" ]),
    mongo: self["mongo_volume_mounted_service"] + devJsonnetTemplate.newMongo(repository, [ "SERVICE_27017_NAME=_mongo._tcp" ]),
    scrapyd: self["scrapyd_volume_mounted_service"] + 
      devJsonnetTemplate.newScrapyd(repository, ["sh", "-c", "./wait-for-it.sh -t 500 scrapoxy:8888 -- scrapyd"], []) + {
        ports: [ "6800" ],
      },
    scrapoxy: self["base_service"] + {
      image: repository + "scrapoxy:latest",
      mem_limit: "300m",
      ports: [ "8888:8888", "8889:8889" ],
      environment: devJsonnetTemplate.aws_env + [
        "SERVICE_8888_NAME=_scrapoxy._tcp",
        "PROVIDERS_AWSEC2_ACCESSKEYID=" + std.extVar("AWS_ACCESS_KEY_ID"),
        "PROVIDERS_AWSEC2_SECRETACCESSKEY=" + std.extVar("AWS_SECRET_ACCESS_KEY"),
        "COMMANDER_PASSWORD=foobar123",
        "PROVIDERS_AWSEC2_REGION=" + std.extVar("AWS_DEFAULT_REGION"),
        "PROVIDERS_AWSEC2_INSTANCE_INSTANCETYPE=t2.nano",
      ],
      command: [ "./doit.sh" ],
    },
  },
}
