# =============================================================================
# terraform/modules/cost-control/main.tf
#
# Lambda-based cost control for PetClinic dev environment.
#
# What it does:
#   stop   → stops RDS instance + scales EKS nodes to 0
#   start  → starts RDS instance + scales EKS nodes back to min
#   status → returns current state of both resources
#
# Auto-destroy timer: scripts/cost-control.sh --apply records a Unix timestamp
# in SSM Parameter Store. A cron job runs --check every 30 min; if 7 hours
# have elapsed the user gets a 60-second prompt before terraform destroy fires.
#
# Triggered by: scripts/cost-control.sh
# =============================================================================

locals {
  name = "${var.project}-${var.environment}-cost-control"
}

# ── Package the Lambda handler into a ZIP ────────────────────────────────────
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda/cost_control.zip"
}

# ── IAM role the Lambda function assumes ─────────────────────────────────────
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  description        = "Execution role for the PetClinic cost-control Lambda"

  tags = { Name = "${local.name}-role" }
}

# Basic Lambda execution — CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Permissions to stop/start RDS and scale EKS node group
data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid    = "RDSStopStart"
    effect = "Allow"
    actions = [
      "rds:StopDBInstance",
      "rds:StartDBInstance",
      "rds:DescribeDBInstances",
    ]
    resources = [
      "arn:aws:rds:${var.aws_region}:${var.aws_account_id}:db:${var.rds_identifier}"
    ]
  }

  statement {
    sid    = "EKSScaleNodes"
    effect = "Allow"
    actions = [
      "eks:UpdateNodegroupConfig",
      "eks:DescribeNodegroup",
      "eks:DescribeCluster",
    ]
    resources = [
      "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${var.eks_cluster_name}",
      "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:nodegroup/${var.eks_cluster_name}/${var.eks_nodegroup_name}/*",
    ]
  }

  statement {
    sid    = "SSMTimestamp"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter",
      "ssm:DeleteParameter",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/petclinic/${var.environment}/cost-control/*"
    ]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${local.name}-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 7

  tags = { Name = "${local.name}-logs" }
}

# ── Lambda Function ───────────────────────────────────────────────────────────
resource "aws_lambda_function" "cost_control" {
  function_name    = local.name
  description      = "Stop/start PetClinic RDS and EKS nodes on demand to save AWS credits"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      RDS_IDENTIFIER = var.rds_identifier
      EKS_CLUSTER    = var.eks_cluster_name
      EKS_NODEGROUP  = var.eks_nodegroup_name
      NODE_MIN       = tostring(var.node_min)
      NODE_MAX       = tostring(var.node_max)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = { Name = local.name }
}

# ── IAM permission — allows the invoking user/role to call this Lambda ────────
# This lets the cost-control.sh script (running as paul's IAM user) invoke it.
resource "aws_lambda_permission" "allow_account_invoke" {
  statement_id  = "AllowAccountInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_control.function_name
  principal     = "arn:aws:iam::${var.aws_account_id}:root"
}
