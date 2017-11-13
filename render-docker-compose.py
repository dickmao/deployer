#!/usr/bin/python

from __future__ import print_function
from os.path import join, realpath
import os, errno, operator, re, sys, subprocess, signal
import jinja2
import yaml
import argparse
import json
import _jsonnet
import fnmatch

wdir = os.path.dirname(realpath(__file__))

def render(tpl_path, context):
    path, filename = os.path.split(tpl_path)
    return jinja2.Environment(
        loader=jinja2.FileSystemLoader(path or './')
    ).get_template(filename).render(context)

def get_jsonnet(which):
    matches = []
    for root, dirnames, filenames in os.walk(wdir):
        for filename in fnmatch.filter(filenames, '*.jsonnet'):
            if filename == which or '.'.join(filename.split('.')[0:-1]) == which:
                return filename


parser = argparse.ArgumentParser()
parser.add_argument('--var', nargs='*')
parser.add_argument('jsonnet', nargs='?', default='dev')
args = parser.parse_args()
ext_vars = {}
if args.var:
    try:
        ext_vars = { k: v for k,v in (binding.split('=') for binding in args.var) }
    except ValueError as e:
        print("ERROR Problem with '{}': {}".format(' '.join(['--var'] + args.var), e.message), file=sys.stderr)
        raise
jsonnet = get_jsonnet(args.jsonnet)
if not jsonnet:
    raise IOError('{} not found'.format(args.jsonnet))
print(_jsonnet.evaluate_file(jsonnet, ext_vars=ext_vars))
