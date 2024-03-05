import boto3
import csv
import logging
import os
import json
from botocore.exceptions import ClientError


def lambda_handler(event, context):
    subject = event['Records'][0]['Sns']['Subject']
    message = event['Records'][0]['Sns']['Message']

    modified_message_content = modify_message_content(message=message)
    ip_list = []
    for item in modified_message_content:
        ip_list.append(item+'/32')
    
    waf_client = boto3.client('wafv2')
    
    waf_result = waf_client.get_ip_set(Name='<NAME>',Scope='<SCOPE>',Id='<IP SET ID>')
    token = waf_result['LockToken']
    response = waf_client.update_ip_set(Name='<NAME>',Scope='<SCOPE>',Id='<IP SET ID>',Description='<...>',Addresses=ip_list,LockToken=token)


def modify_message_content(message):
    modified_message_content = list(message.split(","))[:1]
    print(modified_message_content)
    return modified_message_content