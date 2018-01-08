#!/bin/bash -ex

IFS=$'\n'
for bf in $(s3cmd ls) ; do
    buck=${bf##* }
    spider=${bf##*.} 
    dir=/var/lib/scrapyd/items/tutorial/$spider
    mkdir -m 0775 -p $dir
    mf=$(s3cmd ls $buck/Marker. | sort | tail -1)
    marker=${mf##* }
    if [ ! -e $dir/$(basename marker) ] ; then
        s3cmd get $marker $dir/
    fi
done
