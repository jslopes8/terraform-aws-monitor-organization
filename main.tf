#############################################################################################################################
#
# Monitor Import Change in AWS Organizations with Microsoft Teams Channel
#

## Obter Account ID
data "aws_caller_identity" "current" {}

## Obter AWS Regions
data "aws_region" "current" {}

#############################################################################################################################
#
# SNS Topic Protocol HTTPS: Endpoint Lambda
#

module "sns_topic" {
  source = "git::https://github.com/jslopes8/terraform-aws-sns.git?ref=v0.3"

  subscriptions_endpoint = [{
    name          = local.stack_name
    display_name  = "${local.stack_name} OrganizationsEvent"
    protocol      = "lambda"
    endpoint      = module.create_lambda.arn

    ## This policy defines who can access your topic. 
    ## By default, only the topic owner can publish or subscribe to the topic.
    access_policy = [
      {
        sid     = "__default_statement_ID"
        effect  = "Allow"
        principals = {
          type  = "AWS"
          identifiers = ["*"]
        }
        actions = [
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:AddPermission",
          "SNS:RemovePermission",
          "SNS:DeleteTopic",
          "SNS:Subscribe",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish",
          "SNS:Receive"
        ]
        resources = [
          "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${local.stack_name}*" 
        ]
        condition = {
          test      = "StringEquals"
          variable  = "AWS:SourceOwner"
          values    = [ data.aws_caller_identity.current.account_id ]
        }
      },
      {
        sid = "AWSEvents"
        effect = "Allow"
        principals = {
          type = "Service"
          identifiers = ["events.amazonaws.com"]
        }
        actions = ["sns:Publish"]
        resources = [
          "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${local.stack_name}*"
        ]
      }
    ]
  }]

  default_tags = local.default_tags
}

#############################################################################################################################
#
# EventBridge: APIs that you want monitored
#

module "eventbridge" {
  source  = "git@github.com:jslopes8/terraform-aws-cw-event-rules.git?ref=v1.1"

  name        = local.stack_name
  description = "${local.stack_name} Rules"

  event_pattern = jsonencode({
    "source": ["aws.organizations"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventSource": ["organizations.amazonaws.com"],
      "eventName": [
        "DetachPolicy", 
        "UpdatePolicy", 
        "DeleteOrganizationalUnit",
        "UpdateOrganizationalUnit",
        "MoveAccount"
      ]
    }
  })

  targets = [
    {
      target_id  = "SendToSNS"
      arn = module.sns_topic.arn["ARN"]
    
      input_transformer = [{
        input_paths = {
          "account":"$.account",
          "actions":"$.detail.eventName",
          "policyId":"$.detail.requestParameters.policyId",
          "sourceIPAddress":"$.detail.sourceIPAddress",
          "target_id":"$.detail.requestParameters.targetId",
          "time":"$.detail.eventTime",
          "user":"$.detail.userIdentity.principalId"
        }
        input_template = "\"Notificação de Mudança em AWS Organizations Account Id <account> em <time> pelo usuario <user> com IP de origem <sourceIPAddress>. Realizou uma ação de <actions> para o policy id <policyId> em <target_id>.\""
      }]
    }
  ]

  default_tags = local.default_tags
}

#############################################################################################################################
#
# IAM Role: Lambda Function
#

module "iam_role_lambda" {
  source = "git::https://github.com/jslopes8/terraform-aws-iam-roles.git?ref=v1.3"

  ## Provide the required information below and review this role before you create it.
  name            = "${local.stack_name}-Role"
  path            = "/service-role/"
  description     = "Allow ${local.stack_name} Notification Microsoft Teams Channel"

  ## Trusted entities - AWS service: lambda.amazonaws.com
  assume_role_policy  = [{
    effect      = "Allow"
    actions     = [ "sts:AssumeRole" ]
    principals  = {
      type        = "Service"
      identifiers = [ "lambda.amazonaws.com" ]
    }
  }]

  ## Attach permissions policies
  iam_policy  = [
    {
      effect    = "Allow"
      actions   = [ "logs:CreateLogGroup" ]
      resources = [ "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*" ]
    },
    {
      effect    = "Allow"
      actions   = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      resources = [ 
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.stack_name}*:*" 
      ]  
    }
  ]
  default_tags = local.default_tags
}

#############################################################################################################################
#
# Lambda Function: WebHook POST
#

module "create_lambda" {
  source = "git::https://github.com/jslopes8/terraform-aws-lamda.git?ref=v0.1.0"

  function_name = local.stack_name
  description   = "${local.stack_name} Notification Microsoft Teams Channel"

  ## Expected Runtime: nodejs nodejs4.3 nodejs6.10 nodejs8.10 nodejs10.x nodejs12.x nodejs14.x java8 java8.al2 java11 python2.7 
  ## python3.6 python3.7 python3.8 dotnetcore1.0 dotnetcore2.0 dotnetcore2.1 dotnetcore3.1 nodejs4.3-edge go1.x 
  ## ruby2.5 ruby2.7 provided provided.al2
  handler = "lambda_function.lambda_handler"
  runtime = "python3.6"
  timeout = "3"
  role    = module.iam_role_lambda.role_arn

  environment = {
    WebHookTeams = "https://test.webhook.office.com/webhookb2/92a06e6ea6"
  }

  archive_file = [{
    type        = "zip"
    source_dir  = "lambda-code"
    output_path = "lambda-code/lambda_function.zip"
  }]

  lambda_permission   = [
    {
      statement_id  = "AllowExecutionFromCloudWatch"
      action        = "lambda:InvokeFunction"
      principal     = "events.amazonaws.com"
      source_arn    = module.eventbridge.cw_arn
    },
    {
      statement_id  = "AllowExecutionFromSNS"
      action        = "lambda:InvokeFunction"
      principal     = "sns.amazonaws.com"
      source_arn    = module.sns_topic.topic_arn
    }
  ]

  default_tags = local.default_tags
}