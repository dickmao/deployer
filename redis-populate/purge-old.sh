#!/bin/bash -ex

host=""
port=""
while [[ $# -gt 0 ]] ; do
  key="$1"
  case "$key" in
      -h)
      host=" -h $2"
      shift
      shift
      ;;
      -p)
      port=" -p $2"
      shift
      shift
      ;;
      *)
      break
      ;;    
  esac
done

while [ 1 ] ; do
    BEFORE=$(date --date="${expire} days ago" +%s)
    for db in $(seq 0 10); do
        for expire in $(seq 1 30); do
          IDS=$(redis-cli${host}${port} -n $db --raw zrangebyscore item.index.posted.${expire} -inf $BEFORE | xargs echo -n)
          if [ ! -z "$IDS" ]; then
            KEYS=$(for i in $IDS; do echo -n "item.$i "; done)
            redis-cli${host}${port} -n $db DEL $KEYS
            redis-cli${host}${port} -n $db zrem item.index.price $IDS
            redis-cli${host}${port} -n $db zrem item.index.bedrooms $IDS
            redis-cli${host}${port} -n $db zrem item.index.score $IDS
            redis-cli${host}${port} -n $db zrem item.geohash.coords $IDS
            redis-cli${host}${port} -n $db zrem item.index.posted.${expire} $IDS
          fi
        done
    done
    sleep 6000
done
