(import "dev.jsonnet") + {
  services+: {
    base_service:: {
      dns_search: std.extVar("cluster") + ".internal",
    },
    scrapyd_volume_mounted_service: self["base_service"] + {
      volumes: [ "/efs/var/lib/scrapyd:/var/lib/scrapyd" ],
    },
    scrapoxy: self["base_service"] + {
      image: "303634175659.dkr.ecr.us-east-2.amazonaws.com/scrapoxy:latest",
      mem_limit: 300000000,
      ports: [ "8888:8888", "8889:8889" ],
      environment: [
        "SERVICE_8888_NAME=_scrapoxy._tcp",
        "AWS_DEFAULT_REGION=" + std.extVar("AWS_DEFAULT_REGION"),
        "AWS_ACCESS_KEY_ID=" + std.extVar("AWS_ACCESS_KEY_ID"),
        "AWS_SECRET_ACCESS_KEY=" + std.extVar("AWS_SECRET_ACCESS_KEY"),
        "PROVIDERS_AWSEC2_ACCESSKEYID=" + std.extVar("AWS_ACCESS_KEY_ID"),
        "PROVIDERS_AWSEC2_SECRETACCESSKEY=" + std.extVar("AWS_SECRET_ACCESS_KEY"),
        "COMMANDER_PASSWORD=foobar123",
        "PROVIDERS_AWSEC2_REGION=us-east-2",
        "PROVIDERS_AWSEC2_INSTANCE_INSTANCETYPE=t2.nano",
      ],
      command: [ "./doit.sh" ],
    },
  },
}
