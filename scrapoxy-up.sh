./ecs-up.sh --template scrapoxy.template --instance-type t2.medium --size 1
./ecs-compose-down.sh
./ecs-compose-up.sh -s scrapoxy -s scrapyd
