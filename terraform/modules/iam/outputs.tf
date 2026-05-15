output "eso_role_arn" {
  description = "IRSA role ARN for External Secrets Operator — TEAM-2 annotates the external-secrets-sa ServiceAccount with this value"
  value       = aws_iam_role.eso.arn
}

output "lb_controller_role_arn" {
  description = "IRSA role ARN for AWS Load Balancer Controller — TEAM-2 annotates the aws-load-balancer-controller ServiceAccount with this value"
  value       = aws_iam_role.lb_controller.arn
}

output "ebs_csi_role_arn" {
  description = "IRSA role ARN for EBS CSI Driver — applied to the ebs-csi-controller-sa ServiceAccount"
  value       = aws_iam_role.ebs_csi.arn
}

output "github_actions_role_arn" {
  description = "OIDC role ARN for app CI (ECR push) — set as AWS_ROLE_ARN in spring-petclinic-microservices repo secrets"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_tf_role_arn" {
  description = "OIDC role ARN for platform CI (Terraform plan/apply) — set as TF_ROLE_ARN in petclinic-platform repo secrets"
  value       = aws_iam_role.github_actions_tf.arn
}

output "karpenter_node_role_arn" {
  description = "Karpenter node role ARN — TEAM-2 adds this to the EKS aws-auth ConfigMap or access entry so provisioned nodes can join the cluster"
  value       = aws_iam_role.karpenter_node.arn
}

output "karpenter_node_instance_profile_arn" {
  description = "Karpenter node instance profile ARN — TEAM-2 sets this in the EC2NodeClass spec so Karpenter can attach the role to new instances"
  value       = aws_iam_instance_profile.karpenter_node.arn
}

output "karpenter_controller_role_arn" {
  description = "IRSA role ARN for Karpenter controller — TEAM-2 annotates the karpenter ServiceAccount in the karpenter namespace with this value"
  value       = aws_iam_role.karpenter_controller.arn
}
