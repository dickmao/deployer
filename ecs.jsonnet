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
    scrapyd_volume_mounted_service:: self["base_service"] + {
      volumes: [ "/efs/var/lib/scrapyd:/var/lib/scrapyd" ],
    },
    redis+: self["base_service"] {
      volumes: [ "/efs/var/lib/redis:/data" ],
    },
    mongo:: self["mongo_volume_mounted_service"],
    # this is a task but libcompose/project needs to read a ServiceConfig
    # and I'm not about to modify libcompose
    # also: docker-compose says "Additional properties are not allowed"
    "once-dedupe": self["scrapyd_volume_mounted_service"] + {
      image: repository + "dedupe:latest",
      mem_reservation: "512m",
      command: "sh -c './wait-for-it.sh -t 500 corenlp:9005 -- ./wait-for-it.sh -t 500 redis:6379 -- ./dedupe-on-demand.sh -s newyork -o'",
      environment: devJsonnetTemplate.aws_env
    },
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
    "ny-frontend": self["base_service"] + devJsonnetTemplate.newPlayApp(repository, play_env) + {
      ports: [ "9000" ],
    },
    "sf-frontend": self["base_service"] + devJsonnetTemplate.newPlayApp(repository, play_env) + {
      ports: [ "9001" ],
      command: [ "-Dconfig.file=conf/sfbay.conf", "-Dhttp.port=9001" ],
    },
    "ny-email": self["base_service"] + devJsonnetTemplate.newPlayEmail(repository, play_env),
    "corenlp": self["base_service"] + devJsonnetTemplate.newCoreNlp(repository, []),
    scrapyd: self["scrapyd_volume_mounted_service"] + 
      devJsonnetTemplate.newScrapyd(repository, ["sh", "-c", "./wait-for-it.sh -t 500 scrapoxy:8888 -- scrapyd"], [ "API_SCRAPOXY_PASSWORD=" + std.extVar("API_SCRAPOXY_PASSWORD") ]) + {
      ports: [ "6800" ],
    },
    scrapoxy: self["base_service"] + {
      image: repository + "scrapoxy:latest",
      mem_limit: "300m",
      ports: [ "8888:8888", "8889:8889" ],
      environment: devJsonnetTemplate.aws_env + [
        "SERVICE_8888_NAME=_scrapoxy._tcp",
        "COMMANDER_PASSWORD=" + std.extVar("API_SCRAPOXY_PASSWORD"),
        "PROVIDERS_AWSEC2_REGION=" + std.extVar("AWS_DEFAULT_REGION"),
        "PROVIDERS_AWSEC2_INSTANCE_INSTANCETYPE=t2.nano",
      ],
      command: [ "./doit.sh" ],
    },
  },
  volumes:: {},
}
