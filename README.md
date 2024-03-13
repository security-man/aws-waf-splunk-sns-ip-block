# AWS WAF Splunk SNS IP Block

## Description

This simple repository contains some terraform code to deploy a handful of resources and some python code that is deployed into a lambda function. The overall flow of data is illustrated below:

![alt text](https://github.com/security-man/aws-waf-splunk-sns-ip-block/blob/main/aws_splunk_sns_diagram.png?raw=true)

## Resources

The terraform code creates the following primary components:

- lambda function based on 'waf_splunk_sns_ip_block_lambda.py'
- SNS topic to receive alerts from Splunk
- SNS topic subscription to lambda function for triggering
- IAM roles and permissions for SNS and lambda
- AWS WAF IP set for Cloudfront and eu-west-2 region

This set of resources also requires the following pre-requisites:

- WAF logs sent via firehose to Splunk
- Splunk alert configured to send malicious IPs to an SNS topic at defined frequency