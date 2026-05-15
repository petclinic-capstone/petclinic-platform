# =============================================================================
# terraform/environments/dev/eks-access.tf
#
# EKS Access Entries — grants kubectl (cluster-admin) to every team member
# listed below.  Access is provisioned automatically at terraform apply
# so the cluster is ready for TEAM-2 ops the moment the infra comes up.
#
# To add or remove a user: edit the eks_cluster_admins list and re-apply.
# No manual aws-auth edits or CLI commands needed.
# =============================================================================

locals {
  eks_cluster_admins = [
    "arn:aws:iam::482352877891:user/dmi-deploy-user01",
    "arn:aws:iam::482352877891:user/dmi-deploy-user02",
    "arn:aws:iam::482352877891:user/dmi-petclinic-infra-pratyush",
    "arn:aws:iam::482352877891:user/petclinic-infra-Aarti",
    "arn:aws:iam::482352877891:user/petclinic-infra-cicd-ntando",
    "arn:aws:iam::482352877891:user/petclinic-infra-paul",
  ]
}

# Register each IAM user as a known principal in the cluster
resource "aws_eks_access_entry" "cluster_admins" {
  for_each = toset(local.eks_cluster_admins)

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  type          = "STANDARD"

  tags = {
    Name = "eks-admin-${basename(each.value)}"
  }
}

# Attach the AWS-managed cluster-admin policy to each access entry
resource "aws_eks_access_policy_association" "cluster_admins" {
  for_each = toset(local.eks_cluster_admins)

  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_admins]
}
