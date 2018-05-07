local play_env = [ 
  "MONGO_HOST=db0:27017,db1:27017,db2",
  "MONGO_AUTH_STRING=" + std.extVar("MONGO_AUTH_STRING"),
  "EIP_ADDRESS=" + std.extVar("EIP_ADDRESS"),
];
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
    redis: self["redis_volume_mounted_service"] + devJsonnetTemplate.newRedis(repository, [ "SERVICE_6379_NAME=_redis._tcp" ]),
    mongo:: self["mongo_volume_mounted_service"],
    # this is a task but libcompose/project needs to read a ServiceConfig
    # and I'm not about to modify libcompose
    # also: docker-compose says "Additional properties are not allowed"
    "mongo-flush": self["base_service"] + devJsonnetTemplate.newMongo(repository, ["sh", "-c", "mongo mongodb://$${MONGO_AUTH_STRING}$${MONGO_HOST}:27017/admin?replicaSet=s0 --eval 'db.shutdownServer({force:true})'"] , play_env) +
    {  
      logging: {
         driver: "awslogs",
         options: {
           "awslogs-group": std.extVar("cluster"),
           "awslogs-region": std.extVar("AWS_DEFAULT_REGION"),
           "awslogs-stream-prefix": "mongo",
         }
      },
    },
    "play-app": self["base_service"] + devJsonnetTemplate.newPlayApp(repository, play_env) + {
      ports: [ "9000" ],
    },
    "play-sf": self["base_service"] + devJsonnetTemplate.newPlayApp(repository, play_env) + {
      ports: [ "9001" ],
      command: [ "-Dconfig.file=conf/sfbay.conf" ],
    },
    "play-email": self["base_service"] + devJsonnetTemplate.newPlayEmail(repository, play_env),
    "corenlp": self["base_service"] + devJsonnetTemplate.newCoreNlp(repository, []) + {
      image: repository + "corenlp@sha256:64ba4830b10b75f4da7abd80f9e05512af3196e2d89ac26383a04495992856f0",
    },
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
  volumes:: {},
}
