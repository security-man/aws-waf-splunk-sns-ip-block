import boto3
import logging
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    subject = event['Records'][0]['Sns']['Subject']
    message = event['Records'][0]['Sns']['Message']
    try:
        modified_message_content = modify_message_content(message=message)
        new_ip = str(modified_message_content)+"/32"
        print(new_ip)
        waf_client_cloudfront = boto3.client('wafv2',region_name='us-east-1')
        waf_client_regional = boto3.client('wafv2',region_name='eu-west-2')
        waf_ip_sets_cloudfront = waf_client_cloudfront.list_ip_sets(
            Scope = 'CLOUDFRONT'
        )
        waf_ip_sets_regional = waf_client_regional.list_ip_sets(
            Scope = 'REGIONAL'
        )
        waf_ip_set_id_cloudfront = ""
        waf_ip_set_id_regional = ""
        for item in waf_ip_sets_cloudfront['IPSets']:
            if item['Name']=="waf-splunk-ip-set-cloudfront":
                waf_ip_set_id_cloudfront = item['Id']
        for item in waf_ip_sets_regional['IPSets']:
            if item['Name']=="waf-splunk-ip-set-regional":
                waf_ip_set_id_regional = item['Id']
        waf_result_cloudfront = waf_client_cloudfront.get_ip_set(
            Name='waf-splunk-ip-set-cloudfront',
            Scope='CLOUDFRONT',
            Id=waf_ip_set_id_cloudfront
        )
        waf_result_regional = waf_client_regional.get_ip_set(
            Name='waf-splunk-ip-set-regional',
            Scope='REGIONAL',
            Id=waf_ip_set_id_regional
        )
        token_cloudfront = waf_result_cloudfront['LockToken']
        token_regional = waf_result_regional['LockToken']
        ip_list_cloudfront = waf_result_cloudfront['IPSet']['Addresses']
        ip_list_regional = waf_result_regional['IPSet']['Addresses']
        ip_list_cloudfront.append(new_ip)
        print(ip_list_cloudfront)
        ip_list_regional.append(new_ip)
        print(ip_list_regional)
        response_cloudfront = waf_client_cloudfront.update_ip_set(
            Name='waf-splunk-ip-set-cloudfront',
            Scope='CLOUDFRONT',
            Id=waf_ip_set_id_cloudfront,
            Description='List of IPs to BLOCK from Splunk due to multiple malicious requests detected',
            Addresses=ip_list_cloudfront,
            LockToken=token_cloudfront
        )
        print(response_cloudfront)
        response_regional = waf_client_regional.update_ip_set(
            Name='waf-splunk-ip-set-regional',
            Scope='REGIONAL',
            Id=waf_ip_set_id_regional,
            Description='List of IPs to BLOCK from Splunk due to multiple malicious requests detected',
            Addresses=ip_list_regional,
            LockToken=token_regional
        )
        print(response_regional)
    except ClientError as e:
        logging.error(e)

def modify_message_content(message):
    print(message)
    message_split = message.split("\"")
    print(message_split[3])
    return_ip = message_split[3]
    return return_ip