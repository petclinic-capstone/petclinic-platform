output "zone_id" {
  value = data.aws_route53_zone.petclinic.zone_id
}

output "zone_name" {
  value = data.aws_route53_zone.petclinic.name
}

output "acm_certificate_arn" {
  description = "ARN of the validated wildcard ACM cert — set as annotation on ALB Ingress"
  value       = aws_acm_certificate_validation.wildcard.certificate_arn
}

output "external_dns_role_arn" {
  description = "IRSA role ARN for External-DNS"
  value       = aws_iam_role.external_dns.arn
}
