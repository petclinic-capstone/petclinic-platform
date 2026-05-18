locals {
  oidc_url = trimprefix(var.oidc_provider_url, "https://")
}

# Route53 Hosted Zone — DATA SOURCE (zone pre-exists, do not manage lifecycle)
data "aws_route53_zone" "petclinic" {
  name         = var.domain_name
  private_zone = false
}

# ACM Wildcard Certificate — *.demo.lulamistack.co
resource "aws_acm_certificate" "wildcard" {
  domain_name               = "*.${var.domain_name}"
  validation_method         = "DNS"
  subject_alternative_names = [var.domain_name]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project}-${var.environment}-wildcard-cert"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Route53 DNS Validation Records
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.petclinic.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# ACM Certificate Validation
resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# External-DNS IRSA Role
data "aws_iam_policy_document" "external_dns_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["system:serviceaccount:external-dns:external-dns"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "${var.project}-${var.environment}-external-dns-role"
  assume_role_policy = data.aws_iam_policy_document.external_dns_trust.json
  description        = "IRSA role - External-DNS manages Route53 records for ALB hostnames"
  tags               = { Name = "${var.project}-${var.environment}-external-dns-role" }
}

data "aws_iam_policy_document" "external_dns_permissions" {
  statement {
    sid       = "ChangeRecordSets"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.petclinic.zone_id}"]
  }

  statement {
    sid    = "ListZonesAndRecords"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "external_dns" {
  name   = "${var.project}-${var.environment}-external-dns-policy"
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns_permissions.json
}
