# Terraform config
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.32"
    }
  }
  # INSERT BACKEND CONFIG AS NEEDED
}

# Terraform provider config
provider "aws" {
  alias   = "default"
  region  = var.region
  profile = var.profile
  default_tags {
    tags = {
      ENVIRONMENT = var.ENVIRONMENT
      PROJECT     = var.PROJECT
    }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = var.profile
  alias   = "us-east-1"
  default_tags {
    tags = {
      ENVIRONMENT = var.ENVIRONMENT
      PROJECT     = var.PROJECT
    }
  }
}

data "aws_caller_identity" "current" {
  provider = aws.default
}

resource "aws_sns_topic" "WAFSplunkTopic" {
  provider          = aws.default
  name              = "waf_splunk_topic"
  kms_master_key_id = var.kms_key_id
  delivery_policy = jsonencode({
    "http" : {
      "defaultHealthyRetryPolicy" : {
        "minDelayTarget" : 20
        "maxDelayTarget" : 20
        "numRetries" : 3
        "numMaxDelayRetries" : 0
        "numNoDelayRetries" : 0
        "numMinDelayRetries" : 0
        "backoffFunction" : "linear"
      },
      "disableSubscriptionOverrides" : false
      "defaultThrottlePolicy" : {
        "maxReceivesPerSecond" : 1
      }
    }
  })
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "__default_policy_ID"
    Statement = [
      {
        Sid    = "__default_statement_ID"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:AddPermission",
          "SNS:RemovePermission",
          "SNS:DeleteTopic",
          "SNS:Subscribe",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish"
        ]
        Resource = join("", ["arn:aws:sns:eu-west-2:", "${data.aws_caller_identity.current.account_id}", ":waf_splunk_topic"])
        Condition = {
          StringEquals = {
            "AWS:SourceOwner" = "${data.aws_caller_identity.current.account_id}"
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "WAFSplunkTopicTarget" {
  provider  = aws.default
  topic_arn = aws_sns_topic.WAFSplunkTopic.arn
  protocol  = "lambda"
  endpoint  = module.lambda_function.lambda_function_arn
}

resource "aws_wafv2_ip_set" "WAFSplunkIPSetCloudFront" {
  provider           = aws.us-east-1
  name               = "waf-splunk-ip-set-cloudfront"
  description        = "A set of IPs updated by Splunk for blocking via WAF for CloudFront"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = []
}

resource "aws_wafv2_ip_set" "WAFSplunkIPSetRegional" {
  provider           = aws.default
  name               = "waf-splunk-ip-set-regional"
  description        = "A set of IPs updated by Splunk for blocking via WAF for eu-west-2"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = []
}

# TO-DO: restrict permissions of lambda to minimum necessary
# TO-DO: re-write lambda as set of resources rather than bloated module
module "lambda_function" {
  providers = {
    aws = aws.default
  }
  source = "terraform-aws-modules/lambda/aws"
  function_name = "waf_splunk_sns_ip_block_lambda"
  description   = "Lambda function to read SNS messages sent from Splunk containing an IP address and writing this IP to a WAF IP set"
  handler       = "waf_splunk_sns_ip_block_lambda.lambda_handler"
  runtime       = "python3.11"
  source_path   = "${path.root}/../lambda"
  attach_policy_json = true
  policy_json   = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = [
            "wafv2:GetIPSet",
            "wafv2:ListIPSets",
            "wafv2:CreateIPSet",
            "wafv2:UpdateIPSet",
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Effect   = "Allow"
          Resource = "*"
        },
      ]
    })
}

resource "aws_lambda_permission" "with_sns" {
  provider      = aws.default
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = "${module.lambda_function.lambda_function_name}"
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.WAFSplunkTopic.arn
}

resource "aws_sns_topic_subscription" "WAFSplunkLambdaSNSSubscription" {
  provider  = aws.default
  topic_arn = aws_sns_topic.WAFSplunkTopic.arn
  protocol  = "lambda"
  endpoint  = "${module.lambda_function.lambda_function_arn}"
}