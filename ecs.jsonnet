(import "dev.jsonnet") + {
  services+: {
    scrapyd_volume_mounted_service: self["base_service"] + {
      volumes: [ "/efs/var/lib/scrapyd:/var/lib/scrapyd" ],
    },
    scrapoxy-setup: self["base_service"] + {
      image: "303634175659.dkr.ecr.us-east-2.amazonaws.com/scrapoxy:latest",
      mem_limit: 300000000,
    },
    scrapoxy: self["base_service"] + {
      image: "303634175659.dkr.ecr.us-east-2.amazonaws.com/scrapoxy:latest",
      mem_limit: 300000000,
      environment: [
        "AWS_DEFAULT_REGION=" + std.extVar("AWS_DEFAULT_REGION"),
        "AWS_ACCESS_KEY_ID=" + std.extVar("AWS_ACCESS_KEY_ID"),
        "AWS_SECRET_ACCESS_KEY=" + std.extVar("AWS_SECRET_ACCESS_KEY"),
        "PROVIDERS_AWSEC2_ACCESSKEYID=" + std.extVar("AWS_ACCESS_KEY_ID"),
        "PROVIDERS_AWSEC2_SECRETACCESSKEY=" + std.extVar("AWS_SECRET_ACCESS_KEY"),
        "COMMANDER_PASSWORD=foobar123",
        "PROVIDERS_AWSEC2_REGION=us-east-2",
        "PROVIDERS_AWSEC2_INSTANCE_INSTANCETYPE=t2.nano",
      ],
      command: "sh -c 'vpc=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$(curl -s http://169.254.169.254/latest/meta-data/mac)/vpc-id); if ! aws ec2 describe-security-groups --output text --filters Name=vpc-id,Values=$vpc,Name=group-name,Values=forward-proxy | grep -q . ; then sgid=$(aws ec2 create-security-group --description forward-proxy --group-name forward-proxy --vpc-id $vpc --output text) && aws ec2 authorize-security-group-ingress --group-id $sgid --protocol tcp --port 3128 --cidr 0.0.0.0/0 ; fi && if ! aws ec2 describe-images --filter Name=name,Values=forward-proxy --output text | grep -q . ; then waitfor=$(aws ec2 copy-image --name forward-proxy --source-image-id ami-06220275 --source-region eu-west-1 --output text) ; while aws ec2 describe-images --image-ids $waitfor --output text | grep -q pending ; do sleep 10 ; done ; fi && PROVIDERS_AWSEC2_INSTANCE_IMAGEID=$(aws ec2 describe-images --filter Name=name,Values=forward-proxy --output text | head -1 | awk \\\'{ print $6 }\\\' ) scrapoxy start tools/docker/config.js -d'",
    },
  },
}