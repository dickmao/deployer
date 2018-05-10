#!/usr/bin/python

import os, re, redis, argparse, requests
import dateutil.parser
import time
from lxml import html

parser = argparse.ArgumentParser()
parser.add_argument('--host', type=str, default='localhost')
parser.add_argument('--port', type=int, default=6379)

args = parser.parse_args()
for db in range(11):
    red = redis.StrictRedis(host=args.host, port=args.port, db=db)
    dels = []
    for i in red.zscan_iter('item.index.score'):
        link = red.hget("item.{}".format(i[0]), 'link')
        try:
            tree = html.fromstring(requests.get(link).content)
            if bool(tree.xpath('//section[@class="body"]//div[@class="removed"]')):
                dels.append(i[0])
        except requests.exceptions.RequestException as e:
            print e, link, i[0]
            dels.append(i[0])

    if dels:
        red.delete(*["item.{}".format(i) for i in dels])
        red.zrem("item.index.price", *dels)
        red.zrem("item.index.bedrooms", *dels)
        red.zrem("item.index.score", *dels)
        red.zrem("item.geohash.coords", *dels)
        for i in range(30):
            red.zrem("item.index.posted.{}".format(i), *dels)
