local devJsonnet = import "dev.jsonnet";
devJsonnet + {
  services+: {
    base_service:: {
      dns_search: std.extVar("cluster") + ".internal",
    },
    scrapyd_volume_mounted_service: self["base_service"] + {
      volumes: [ "/efs/var/lib/scrapyd:/var/lib/scrapyd" ],
    },
    scrapyd: self["scrapyd_volume_mounted_service"] + 
      devJsonnet.newScrapyd(["sh", "-c", "./wait-for-it.sh -t 500 scrapoxy:8888 -- scrapyd"], 
         ["SERVICE_6800_NAME=_scrapyd._tcp",]), 
    scrapoxy: self["base_service"] + {
      image: "303634175659.dkr.ecr.us-east-2.amazonaws.com/scrapoxy:latest",
      mem_limit: 300000000,
      ports: [ "8888:8888", "8889:8889" ],
      environment: devJsonnet.aws_env + [
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
