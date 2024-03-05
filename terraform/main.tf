# Terraform config
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Terraform provider config
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      ENVIRONMENT = var.ENVIRONMENT
      PROJECT     = var.PROJECT
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "WAFSplunkTopic" {
    name = "waf_splunk_topic"
    kms_master_key_id = var.kms_key_id
    delivery_policy = jsonencode({
      Version = "2012-10-17"
      "http": {
        "defaultHealthyRetryPolicy": {
          "minDelayTarget": 20
          "maxDelayTarget": 20
          "numRetries": 3
          "numMaxDelayRetries": 0
          "numNoDelayRetries": 0
          "numMinDelayRetries": 0
          "backoffFunction": "linear"
        },
        "disableSubscriptionOverrides": false
        "defaultThrottlePolicy": {
          "maxReceivesPerSecond": 1
        }
      }
    })
    policy = jsonencode({
      Version = "2012-10-17"
      Id = "__default_policy_ID"
      Statement = [
        {
          Sid = "__default_statement_ID"
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

resource "aws_waf_ipset" "WAFSplunkIPSet" {
  name = "waf-splunk-ip-set"

  ip_set_descriptors {
    type  = "IPV4"
    value = ""
  }
}

output "WAFSplunkIPSetId" {
  value = aws_waf_ipset.WAFSplunkIPSet.id
}

resource "aws_waf_rule" "WAFSplunkIPSetRule" {
  depends_on  = [aws_waf_ipset.WAFSplunkIPSet]
  name        = "waf-splunk-ip-set-rule"
  metric_name = "waf-splunk-ip-set-rule-metric"

  predicates {
    data_id = aws_waf_ipset.WAFSplunkIPSet.id
    negated = false
    type    = "IPMatch"
  }
}

data "aws_iam_policy_document" "LambdaAssumeRole" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "WAFSplunkLambdaIAMRole" {
  name               = "waf_splunk_iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.LambdaAssumeRole.json
}

data "archive_file" "WAFSplunkLambdaCode" {
  type        = "zip"
  source_file = var.lambda_file_path
  output_path = "waf_splunk_lambda_function_payload.zip"
}

resource "aws_lambda_function" "WAFSplunkLambda" {
  depends_on  = [
    aws_waf_ipset.WAFSplunkIPSet,
    aws_waf_rule.WAFSplunkIPSetRule
  ]
  filename      = "waf_splunk_lambda_function_payload.zip"
  function_name = "waf-splunk-ip-set"
  description = "A lambda processor to read SNS messages sent via Splunk containing malicious IPs which then get added to a WAF IP set"
  role          = aws_iam_role.WAFSplunkLambdaIAMRole.arn
  handler       = "index.handler"
  source_code_hash = data.archive_file.LambdaCode.output_base64sha256
  runtime = "nodejs18.x"
  timeout = 180
  memory_size = 128
  reserved_concurrent_executions = -1
  ephemeral_storage {
    size = 512
  }
  tracing_config {
    mode = "PassThrough"
  }
  architectures = [
    "x86_64"
  ]
}