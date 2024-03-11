import boto3
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    subject = event['Records'][0]['Sns']['Subject']
    message = event['Records'][0]['Sns']['Message']

    modified_message_content = modify_message_content(message=message)
    ip_list = []
    for item in modified_message_content:
        ip_list.append(item+'/32')
    
    waf_client_cloudfront = boto3.client('wafv2',region="us-east-1")
    waf_client_regional = boto3.client('wafv2',region="eu-west-2")
    waf_ip_sets_cloudfront = waf_client_cloudfront.list_ip_set(
        Scope = 'CLOUDFRONT'
    )
    waf_ip_sets_regional = waf_client_regional.list_ip_set(
        Scope = 'REGIONAL'
    )
    for item in waf_ip_sets_cloudfront['IPSets']:
        if item['Name']=="waf-splunk-ip-set":
            waf_ip_set_id_cloudfront = item['Id']
    for item in waf_ip_sets_regional['IPSets']:
        if item['Name']=="waf-splunk-ip-set":
            waf_ip_set_id_regional = item['Id']
    
    waf_result_cloudfront = waf_client_cloudfront.get_ip_set(
        Name='waf-splunk-ip-set',
        Scope='CLOUDFRONT',
        Id=waf_ip_set_id_cloudfront
    )
    waf_result_regional = waf_client_regional.get_ip_set(
        Name='waf-splunk-ip-set',
        Scope='REGIONAL',
        Id=waf_ip_set_id_regional
    )
    token_cloudfront = waf_result_cloudfront['LockToken']
    token_regional = waf_result_regional['LockToken']
    response_cloudfront = waf_client_cloudfront.update_ip_set(
        Name='waf-splunk-ip-set',
        Scope='CLOUDFRONT',
        Id=waf_ip_set_id_cloudfront,
        Description='List of IPs to BLOCK from Splunk due to multiple malicious requests detected',
        Addresses=ip_list,
        LockToken=token_cloudfront
    )
    response_regional = waf_client_regional.update_ip_set(
        Name='waf-splunk-ip-set',
        Scope='REGIONAL',
        Id=waf_ip_set_id_regional,
        Description='List of IPs to BLOCK from Splunk due to multiple malicious requests detected',
        Addresses=ip_list,
        LockToken=token_regional
    )

def modify_message_content(message):
    modified_message_content = list(message.split(","))[:1]
    print(modified_message_content)
    return modified_message_content