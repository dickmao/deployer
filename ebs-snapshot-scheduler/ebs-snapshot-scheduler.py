######################################################################################################################
#  Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.                                           #
#                                                                                                                    #
#  Licensed under the Amazon Software License (the "License"). You may not use this file except in compliance        #
#  with the License. A copy of the License is located at                                                             #
#                                                                                                                    #
#      http://aws.amazon.com/asl/                                                                                    #
#                                                                                                                    #
#  or in the "license" file accompanying this file. This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES #
#  OR CONDITIONS OF ANY KIND, express or implied. See the License for the specific language governing permissions    #
#  and limitations under the License.                                                                                #
######################################################################################################################

import argparse
import botocore.exceptions
import datetime
import logging
import os

import boto3
from git import Repo

import pytz

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s', datefmt="%Y-%m-%d %H:%M:%S")
logging.getLogger('botocore').setLevel(logging.WARNING)
logging.getLogger('boto3').setLevel(logging.WARNING)
logger = logging.getLogger()

def branch_of(snapshot):
    branches = [d['Value'] for d in snapshot.tags if d['Key'] == "Branch"]
    if branches:
        return branches[0]
    return git_branch()

def git_branch():
    branch = os.environ.get('GIT_BRANCH') or os.environ.get('CIRCLE_BRANCH')
    if branch:
        return branch
    return Repo("./", search_parent_directories=True).active_branch.name

def backup_instance(instance_obj, region, custom_tag_name, dry=False):
    result = []
    ec2_resource = boto3.resource('ec2', region_name=region)
    for mapping in instance_obj.block_device_mappings:
        if instance_obj.root_device_name == mapping['DeviceName']:
            continue
        volume = ec2_resource.Volume(mapping['Ebs']['VolumeId'])
        name = [kv['Value'] for kv in instance_obj.tags if kv['Key'] == 'Name'][0]
        device = [attachment['Device'] for attachment in volume.attachments][0]
        try:
            snapshot = ec2_resource.create_snapshot(
                DryRun=dry, VolumeId=volume.id, TagSpecifications=[
                    { 'ResourceType': 'snapshot',
                      'Tags': [ { 'Key': 'Name', 'Value': name },
                                { 'Key': 'Device', 'Value': device },
                                { 'Key': 'Branch', 'Value': branch_of(ec2_resource.Snapshot(volume.snapshot_id)) },
                                { 'Key': custom_tag_name, 'Value': "auto_delete" },
                      ]}])
            logger.info("Snapped {} {}".format(volume.id, device))
            result.append(snapshot.id)
        except botocore.exceptions.ClientError:
            if dry:
                logger.info("Would snap {} {}".format(volume.id, device))
            else:
                logger.error("Failed create {} {}".format(volume.id, device))
    return result


def parse_date(dt_string):
    return datetime.datetime.strptime(dt_string, '%Y-%m-%d %H:%M:%S.%f')


# Purge snapshots both scheduled and manually deleted
def purge_history(region, custom_tag_name, retention_days, dry=False):
    ec2_resource = boto3.resource('ec2', region_name=region)
    for snap in ec2_resource.snapshots.filter(OwnerIds=['self'],
                                              Filters=[{ 'Name': 'tag-key',
                                                         'Values': [ custom_tag_name ] }, ]):
        delta = datetime.datetime.utcnow().replace(tzinfo=pytz.utc) - snap.start_time
        if delta.seconds >= 86400*retention_days:
            try:
                response = snap.delete(DryRun=dry)
                if response['ResponseMetadata']['HTTPStatusCode'] == 200:
                    logger.info("Deleted {} ({} seconds old)".format(snap.id, delta.seconds))
                else:
                    logger.error("Failed delete {} ({} seconds old)".format(snap.id, delta.seconds))
            except botocore.exceptions.ClientError:
                if dry:
                    logger.info("Would delete {} ({} seconds old)".format(snap.id, delta.seconds))
                else:
                    logger.error("Failed delete {} ({} seconds old)".format(snap.id, delta.seconds))

def is_int(s):
    try:
        int(s)
        return True
    except ValueError:
        return False

def get_output_value(response, key):
    return [e['OutputValue'] for e in response['Stacks'][0]['Outputs'] if e['OutputKey'] == key][0]

def lambda_handler(event, context):
    cf_client = boto3.client('cloudformation')
    stacks = cf_client.list_stacks(StackStatusFilter=['CREATE_COMPLETE'])['StackSummaries']
    stack_prefix = context.invoked_function_arn.split(':')[6].rsplit('-', 2)[0]
    try:
        stack_name = [stack['StackName'] for stack in stacks if stack['StackName'].startswith(stack_prefix)][0]
    except IndexError:
        logger.error("No stack begins with {}".format(stack_prefix))
        return
    response = cf_client.describe_stacks(StackName=stack_name)
    dynamodb = boto3.resource('dynamodb')
    policy_table = dynamodb.Table(get_output_value(response, 'PolicyDDBTableName'))
    item = policy_table.get_item(Key={ 'SolutionName': 'EbsSnapshotScheduler' })['Item']
    custom_tag_name = str(item['CustomTagName'])
    custom_tag_length = len(custom_tag_name)
    snapshot_time = str(item['DefaultSnapshotTime'])
    auto_snapshot_deletion = str(item['AutoSnapshotDeletion']).lower()
    time_zone = str(item['DefaultTimeZone'])
    days_active = str(item['DefaultDaysActive']).lower()
    retention_days = int(item['DefaultRetentionDays'])
    utc_time = datetime.datetime.utcnow()
    # time_delta must be changed before updating the CWE schedule for Lambda
    time_delta = datetime.timedelta(minutes=4)
    region = context.invoked_function_arn.split(':')[3]

    if auto_snapshot_deletion == "yes":
        purge_history(region, custom_tag_name, retention_days)

    # Filter Instances for Scheduler Tag
    ec2_resource = boto3.resource('ec2', region_name=region)
    for i in ec2_resource.instances.all():
        for t in i.tags:
            if t['Key'][:custom_tag_length] == custom_tag_name:
                tz = pytz.timezone(time_zone)
                now = utc_time.replace(tzinfo=pytz.utc).astimezone(tz).strftime("%H%M")
                now_max = utc_time.replace(tzinfo=pytz.utc).astimezone(tz) - time_delta
                now_max = now_max.strftime("%H%M")
                now_day = utc_time.replace(tzinfo=pytz.utc).astimezone(tz).strftime("%a").lower()
                active_day = False

                # Days Interpreter
                if days_active == "all":
                    active_day = True
                elif days_active == "weekdays":
                    weekdays = ['mon', 'tue', 'wed', 'thu', 'fri']
                    if now_day in weekdays:
                        active_day = True
                else:
                    for d in days_active.split(","):
                        if d.lower() == now_day:
                            active_day = True

                # Append to start list
                if snapshot_time >= str(now_max) and snapshot_time <= str(now) and \
                   active_day is True:
                    backup_instance(instance, region, custom_tag_name)
                break

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--region', default="us-east-2")
    parser.add_argument('--nodry', action="store_true")
    parser.add_argument('cluster')
    args = parser.parse_args()

    cf_client = boto3.client('cloudformation')
    stacks = cf_client.list_stacks(StackStatusFilter=['CREATE_COMPLETE'])['StackSummaries']
    stack_prefix = "{}-SnapshotStack-".format(args.cluster)
    try:
        stack_name = [stack['StackName'] for stack in stacks if stack['StackName'].startswith(stack_prefix)][0]
    except IndexError:
        logger.error("No stack begins with {}".format(stack_prefix))
        raise

    response = cf_client.describe_stacks(StackName=stack_name)
    policy_table = boto3.resource('dynamodb').Table(get_output_value(response, 'PolicyDDBTableName'))
    item = policy_table.get_item(Key={ 'SolutionName': 'EbsSnapshotScheduler' })['Item']
    custom_tag_name = str(item['CustomTagName'])

    purge_history(args.region, custom_tag_name, 1, not args.nodry)

    for instance in boto3.resource('ec2', region_name=args.region).instances.filter(Filters=[{ 'Name': 'tag-key', 'Values': [ custom_tag_name ] }]):
        backup_instance(instance, args.region, custom_tag_name, not args.nodry)
