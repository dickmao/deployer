#!/usr/bin/python

from __future__ import print_function

import argparse
import os
import sys
from os.path import join, realpath

import jinja2
import boto3
from six import next


wdir = os.path.dirname(realpath(__file__))

parser = argparse.ArgumentParser()
parser.add_argument('--var', nargs='*', action='append')
parser.add_argument('--outdir', default="/var/tmp")
parser.add_argument('--region', default="us-east-2")
parser.add_argument('template', nargs='+')
args = parser.parse_args()
supp_dict = dict()
if args.var:
    try:
        supp_dict = { k: v for k,v in (binding.split('=') for binding in args.var) }
    except ValueError as e:
        print("ERROR Problem with '{}': {}".format(' '.join(['--var'] + args.var), e.message), file=sys.stderr)
        raise
jinja_env = jinja2.Environment(loader=jinja2.FileSystemLoader(wdir),
                               trim_blocks=True, lstrip_blocks=True, extensions = ["jinja2.ext.do"])

def aws_snapshot_of(name, device):
    ec2_resource = boto3.resource('ec2', region_name=args.region)
    snaps = ec2_resource.snapshots.filter(Filters=[
        { 'Name': 'tag:Name','Values': [name] },
        { 'Name': 'tag:Device','Values': [device] },
    ])
    return next((x.id for x in snaps), "")

jinja_env.filters['aws_snapshot_of'] = aws_snapshot_of
for template in args.template:
    with open(join(args.outdir, template), 'w') as fp:
        fp.write(jinja_env.get_template(template).render(supp_dict))
