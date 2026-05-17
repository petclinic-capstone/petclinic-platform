# =============================================================================
# terraform/modules/cloudwatch/main.tf
#
# CloudWatch observability for PetClinic EKS.
#
# What this provisions:
#   - Log group for EKS control plane (API, audit, auth, scheduler, CM)
#   - Log groups for application pods (via FluentBit — installed via Helm)
#   - CloudWatch Container Insights namespace (metrics — installed via Helm)
#
# Note: The CloudWatch agent and FluentBit DaemonSets are installed via Helm
# in Phase 3, not via Terraform. This module provisions the IAM and log groups
# that those Helm charts require to exist first.
# =============================================================================

locals {
  name_prefix = "${var.project}-${var.environment}"
}

# ── Log Groups ────────────────────────────────────────────────────────────────
# NOTE: /aws/eks/${cluster_name}/cluster is created by the EKS module so that
# the aws_eks_cluster resource can reference it in depends_on. This module
# does NOT recreate that group — it only stores the name for output consumption.

# Application pod logs (fed by FluentBit DaemonSet installed via Helm)
resource "aws_cloudwatch_log_group" "eks_application" {
  name              = "/aws/eks/${var.cluster_name}/application"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.cluster_name}-application-logs" }
}

# Host/node-level logs (fed by CloudWatch agent on nodes)
resource "aws_cloudwatch_log_group" "eks_host" {
  name              = "/aws/eks/${var.cluster_name}/host"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.cluster_name}-host-logs" }
}

# ── Container Insights Metric Namespace ───────────────────────────────────────
# The actual metrics are pushed by the CloudWatch agent (Helm-installed).
# This SSM parameter tells the agent which namespace to use.
resource "aws_ssm_parameter" "container_insights" {
  name  = "/petclinic/${var.environment}/cloudwatch/container-insights-namespace"
  type  = "String"
  value = "ContainerInsights"
  tags  = { Name = "${local.name_prefix}-container-insights-namespace" }
}

# ── CloudWatch Dashboard ──────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "petclinic" {
  dashboard_name = "${local.name_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type       = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EKS Node CPU Utilisation"
          region = var.aws_region
          metrics = [
            ["ContainerInsights", "node_cpu_utilization",
             "ClusterName", var.cluster_name]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type       = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EKS Node Memory Utilisation"
          region = var.aws_region
          metrics = [
            ["ContainerInsights", "node_memory_utilization",
             "ClusterName", var.cluster_name]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type       = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Pod Restart Count (all namespaces)"
          region = var.aws_region
          metrics = [
            ["ContainerInsights", "pod_number_of_container_restarts",
             "ClusterName", var.cluster_name]
          ]
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type       = "log"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "EKS Auth Errors (last 1h)"
          region  = var.aws_region
          query   = "SOURCE '/aws/eks/${var.cluster_name}/cluster' | filter @logStream like 'authenticator' | filter @message like /Error/ | stats count() by bin(5m)"
          view    = "timeSeries"
        }
      }
    ]
  })
}

# ── Cost Control Alarm ────────────────────────────────────────────────────────
# Triggers when estimated AWS charges exceed the threshold.
resource "aws_cloudwatch_metric_alarm" "billing_alert" {
  alarm_name          = "${local.name_prefix}-billing-alert"
  alarm_description   = "Alert when estimated AWS charges exceed threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 86400   # Daily check
  statistic           = "Maximum"
  threshold           = var.billing_alert_threshold
  treat_missing_data  = "notBreaching"

  dimensions = { Currency = "USD" }

  alarm_actions = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []

  tags = { Name = "${local.name_prefix}-billing-alert" }
}
