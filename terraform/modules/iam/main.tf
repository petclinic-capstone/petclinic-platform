# =============================================================================
# terraform/modules/iam/main.tf
#
# Keycards for the five roles that need AWS access:
#
#   1. petclinic-{env}-eso-role           External Secrets Operator       (TEAM-2)
#   2. petclinic-{env}-lb-controller-role AWS Load Balancer Controller    (TEAM-2)
#   3. petclinic-{env}-ebs-csi-role       EBS CSI Driver                  (TEAM-2)
#   4. petclinic-github-actions-role      GitHub Actions app CI (ECR push)(TEAM-3)
#   5. petclinic-github-actions-tf-role   GitHub Actions platform CI (TF) (TEAM-1)
#
# Tags: Project / Environment / Team / ManagedBy are applied automatically by
# the AWS provider default_tags in provider.tf. Each resource only sets Name.
# =============================================================================

locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = "${var.project}-${var.environment}"

  # Strip the https:// prefix from the OIDC URL.
  # IAM trust policy condition keys require the bare hostname, not a full URL.
  # e.g. "oidc.eks.us-east-1.amazonaws.com/id/XXXX"  - not "https://..."
  oidc_url = trimprefix(var.oidc_provider_url, "https://")
}


# =============================================================================
# 1. EXTERNAL SECRETS OPERATOR (ESO)
#    Kubernetes SA : external-secrets-sa   namespace: external-secrets
#    Room it opens : Secrets Manager - the exact RDS master password secret
# =============================================================================

data "aws_iam_policy_document" "eso_trust" {
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
      values   = ["system:serviceaccount:external-secrets:external-secrets-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${local.name_prefix}-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_trust.json
  description        = "IRSA role - External Secrets Operator reads RDS credentials from Secrets Manager"

  tags = {
    Name = "${local.name_prefix}-eso-role"
  }
}

data "aws_iam_policy_document" "eso_permissions" {
  statement {
    sid    = "ReadRDSSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    # Scoped to the exact RDS secret ARN - not a broad path wildcard
    resources = [var.rds_secret_arn]
  }

  statement {
    sid    = "ReadAppSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    # Covers all manually created app secrets: openai-api-key, claude-api-key, etc.
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:petclinic/*"
    ]
  }
}

# Inline policy - avoids iam:CreatePolicy (blocked by DMI course deny policy)
resource "aws_iam_role_policy" "eso" {
  name   = "${local.name_prefix}-eso-policy"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_permissions.json
}


# =============================================================================
# 2. AWS LOAD BALANCER CONTROLLER
#    Kubernetes SA : aws-load-balancer-controller   namespace: kube-system
#    Room it opens : EC2 / ELB - creates and manages the Application Load Balancer
# =============================================================================

data "aws_iam_policy_document" "lb_controller_trust" {
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
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${local.name_prefix}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_trust.json
  description        = "IRSA role - AWS Load Balancer Controller creates and manages the ALB"

  tags = {
    Name = "${local.name_prefix}-lb-controller-role"
  }
}

data "aws_iam_policy_document" "lb_controller_permissions" {

  statement {
    sid    = "DescribeNetworkResources"
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:DescribeCoipPools",
      "ec2:GetCoipPoolUsage",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageSecurityGroupRules"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageLoadBalancers"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:SetWebAcl",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CertificateAndCognito"
    effect = "Allow"
    actions = [
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "cognito-idp:DescribeUserPoolClient",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TagResources"
    effect = "Allow"
    actions = [
      "tag:GetResources",
      "tag:TagResources",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "ServiceLinkedRole"
    effect  = "Allow"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }
}

# Inline policy - avoids iam:CreatePolicy (blocked by DMI course deny policy)
resource "aws_iam_role_policy" "lb_controller" {
  name   = "${local.name_prefix}-lb-controller-policy"
  role   = aws_iam_role.lb_controller.id
  policy = data.aws_iam_policy_document.lb_controller_permissions.json
}


# =============================================================================
# 3. EBS CSI DRIVER
#    Kubernetes SA : ebs-csi-controller-sa   namespace: kube-system
#    Room it opens : EBS storage - provisions volumes for Prometheus and Grafana
# =============================================================================

data "aws_iam_policy_document" "ebs_csi_trust" {
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
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust.json
  description        = "IRSA role - EBS CSI Driver provisions persistent storage volumes"

  tags = {
    Name = "${local.name_prefix}-ebs-csi-role"
  }
}

# AWS provides a managed policy for the EBS CSI Driver - no custom policy needed
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}


# =============================================================================
# 4. GITHUB ACTIONS CI ROLE
#    Used by  : TEAM-3 GitHub Actions workflows
#    Room it opens : ECR only - push Docker images, nothing else
#    No Kubernetes SA - trust is based on GitHub's OIDC identity token
# =============================================================================

# GitHub OIDC provider — managed as a resource so terraform destroy on -target=module.iam
# does not accidentally delete it. lifecycle.prevent_destroy guards against full destroys.
# If EntityAlreadyExists on first apply: import with:
#   terraform import module.iam.aws_iam_openid_connect_provider.github \
#     arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Each entry in github_repo is a full "org/repo" path, allowing repos from
    # different GitHub organisations to share this role.
    # Examples:
    #   "lua-cloud03/spring-petclinic-microservices"  ← TEAM-1 lead test fork
    #   "petclinic-project/petclinic-platform"         ← team platform repo
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for repo in var.github_repo : "repo:${repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
  description        = "Keyless CI role - GitHub Actions pushes images to ECR via OIDC, no stored AWS keys"

  tags = {
    Name = "${var.project}-github-actions-role"
  }
}

data "aws_iam_policy_document" "github_actions_permissions" {
  # ECR login token - account-scoped, required before any docker push
  statement {
    sid       = "ECRLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Image push - scoped to petclinic ECR repos only, nothing else in the account
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/${var.project}-${var.environment}/*"
    ]
  }
}

# Inline policy - avoids iam:CreatePolicy (blocked by DMI course deny policy)
resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.project}-github-actions-ecr-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}


# =============================================================================
# 4b. GITHUB ACTIONS PLATFORM CI ROLE  (TERRAFORM PLAN / APPLY)
#     Used by  : petclinic-project/petclinic-platform GitHub Actions
#     Workflow : terraform-ci.yml  — plan on PR, apply on push to main
#     Secret   : TF_ROLE_ARN  (different from AWS_ROLE_ARN used by app CI)
#
#     Why a separate role?
#       The app CI role (above) only needs ECR push — narrow and safe.
#       Running Terraform requires S3 state, DynamoDB locks, and full CRUD
#       over EKS / RDS / VPC / ECR / IAM / SecretsManager.
#       Merging these into one role violates least privilege: a compromised
#       app build pipeline would gain Terraform-level infra write access.
# =============================================================================

data "aws_iam_policy_document" "github_actions_tf_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Trusts the platform repo only — full org/repo paths, same pattern as app CI.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for repo in var.github_tf_repos : "repo:${repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions_tf" {
  name               = "${var.project}-github-actions-tf-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_tf_trust.json
  description        = "CI role for petclinic-platform - terraform plan/apply via OIDC, no stored AWS keys"

  tags = { Name = "${var.project}-github-actions-tf-role" }
}

data "aws_iam_policy_document" "github_actions_tf_permissions" {

  # ── Terraform state backend ────────────────────────────────────────────────
  statement {
    sid    = "TerraformStateBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
      "s3:ListBucket", "s3:GetBucketVersioning",
    ]
    resources = [
      "arn:aws:s3:::${var.project}-terraform-state-${var.aws_account_id}",
      "arn:aws:s3:::${var.project}-terraform-state-${var.aws_account_id}/*",
    ]
  }

  statement {
    sid    = "TerraformLockTable"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.project}-terraform-locks",
    ]
  }

  # data.aws_caller_identity in provider.tf
  statement {
    sid       = "CallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # ── VPC / Networking ───────────────────────────────────────────────────────
  statement {
    sid    = "VPCManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets", "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:DescribeInternetGateways",
      "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:DescribeRouteTables",
      "ec2:CreateRoute", "ec2:DeleteRoute",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:DescribeSecurityGroups",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags",
      "ec2:DescribeAvailabilityZones", "ec2:DescribeAccountAttributes",
      "ec2:DescribeNetworkInterfaces", "ec2:DescribeSecurityGroupRules",
    ]
    resources = ["*"]
  }

  # ── EKS ───────────────────────────────────────────────────────────────────
  statement {
    sid    = "EKSManagement"
    effect = "Allow"
    actions = [
      "eks:CreateCluster", "eks:DeleteCluster", "eks:DescribeCluster",
      "eks:UpdateClusterConfig", "eks:UpdateClusterVersion", "eks:ListClusters",
      "eks:CreateNodegroup", "eks:DeleteNodegroup", "eks:DescribeNodegroup",
      "eks:UpdateNodegroupConfig", "eks:UpdateNodegroupVersion", "eks:ListNodegroups",
      "eks:CreateAddon", "eks:DeleteAddon", "eks:DescribeAddon", "eks:UpdateAddon", "eks:ListAddons",
      "eks:TagResource", "eks:UntagResource", "eks:ListTagsForResource",
      "eks:AssociateIdentityProviderConfig", "eks:DescribeIdentityProviderConfig",
      "eks:CreateAccessEntry", "eks:DeleteAccessEntry", "eks:DescribeAccessEntry",
    ]
    resources = ["*"]
  }

  # ── RDS ───────────────────────────────────────────────────────────────────
  statement {
    sid    = "RDSManagement"
    effect = "Allow"
    actions = [
      "rds:CreateDBInstance", "rds:DeleteDBInstance", "rds:DescribeDBInstances",
      "rds:ModifyDBInstance", "rds:StopDBInstance", "rds:StartDBInstance",
      "rds:CreateDBSubnetGroup", "rds:DeleteDBSubnetGroup", "rds:DescribeDBSubnetGroups",
      "rds:CreateDBParameterGroup", "rds:DeleteDBParameterGroup",
      "rds:DescribeDBParameterGroups", "rds:ModifyDBParameterGroup",
      "rds:AddTagsToResource", "rds:ListTagsForResource", "rds:RemoveTagsFromResource",
      "rds:DescribeDBSnapshots", "rds:CreateDBSnapshot", "rds:DeleteDBSnapshot",
      "rds:DescribeOrderableDBInstanceOptions", "rds:DescribeEngineDefaultParameters",
    ]
    resources = ["*"]
  }

  # ── ECR ───────────────────────────────────────────────────────────────────
  statement {
    sid    = "ECRManagement"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories",
      "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy", "ecr:DeleteLifecyclePolicy",
      "ecr:SetRepositoryPolicy", "ecr:GetRepositoryPolicy", "ecr:DeleteRepositoryPolicy",
      "ecr:TagResource", "ecr:UntagResource", "ecr:ListTagsForResource",
      "ecr:PutImageScanningConfiguration", "ecr:PutImageTagMutability",
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  # ── IAM — scoped to petclinic-* only ──────────────────────────────────────
  statement {
    sid    = "IAMRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:ListRoles",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
      "iam:TagRole", "iam:UntagRole", "iam:PassRole",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile", "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
    ]
    resources = [
      "arn:aws:iam::${var.aws_account_id}:role/${var.project}-*",
      "arn:aws:iam::${var.aws_account_id}:instance-profile/${var.project}-*",
    ]
  }

  statement {
    sid    = "IAMOIDCProvider"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders",
      "iam:TagOpenIDConnectProvider", "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = ["*"]
  }

  # ── Secrets Manager — scoped to petclinic prefix ──────────────────────────
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret", "secretsmanager:ListSecrets",
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.project}*",
    ]
  }
}

resource "aws_iam_role_policy" "github_actions_tf" {
  name   = "${var.project}-github-actions-tf-policy"
  role   = aws_iam_role.github_actions_tf.id
  policy = data.aws_iam_policy_document.github_actions_tf_permissions.json
}


# =============================================================================
# 5. KARPENTER
#    Role A : petclinic-{env}-karpenter-node-role
#             Assumed by EC2 instances Karpenter launches - same trust as any
#             EKS worker node (ec2.amazonaws.com), not IRSA.
#             Needs an instance profile so EC2 can attach it to new instances.
#
#    Role B : petclinic-{env}-karpenter-controller-role
#             IRSA role for the Karpenter controller pod running in the cluster.
#             Kubernetes SA : karpenter   namespace: karpenter
#             Calls EC2 directly to launch/terminate nodes - bypasses managed
#             node groups entirely.
#
#    TEAM-2 consumes:
#      - karpenter_node_role_arn            -> aws-auth ConfigMap / access entry
#      - karpenter_node_instance_profile_arn -> EC2NodeClass spec
#      - karpenter_controller_role_arn       -> Helm values / SA annotation
# =============================================================================

# -----------------------------------------------------------------------------
# 5a. KARPENTER NODE ROLE
#     EC2 instances launched by Karpenter assume this role on boot.
#     Uses AWS managed policies - no iam:CreatePolicy needed.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "karpenter_node_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_node" {
  name               = "${local.name_prefix}-karpenter-node-role"
  assume_role_policy = data.aws_iam_policy_document.karpenter_node_trust.json
  description        = "Node role for EC2 instances provisioned by Karpenter"

  tags = {
    Name = "${local.name_prefix}-karpenter-node-role"
  }
}

# Four AWS managed policies required by any EKS worker node
resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile - EC2 requires this wrapper to attach an IAM role to an instance
resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${local.name_prefix}-karpenter-node-profile"
  role = aws_iam_role.karpenter_node.name

  tags = {
    Name = "${local.name_prefix}-karpenter-node-profile"
  }
}


# -----------------------------------------------------------------------------
# 5b. KARPENTER CONTROLLER ROLE (IRSA)
#     The Karpenter pod inside the cluster uses this to call AWS APIs.
#     Trust is OIDC-based - same pattern as ESO, LB Controller, EBS CSI.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "karpenter_controller_trust" {
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
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${local.name_prefix}-karpenter-controller-role"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_trust.json
  description        = "IRSA role - Karpenter controller provisions and terminates EC2 nodes"

  tags = {
    Name = "${local.name_prefix}-karpenter-controller-role"
  }
}

data "aws_iam_policy_document" "karpenter_controller_permissions" {

  # Launch and terminate EC2 instances on behalf of the cluster
  statement {
    sid    = "AllowNodeProvisioning"
    effect = "Allow"
    actions = [
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateTags",
      "ec2:DeleteLaunchTemplate",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
    ]
    resources = ["*"]
  }

  # Read-only EC2 describes - needed to pick the right instance type / subnet / AZ
  statement {
    sid    = "AllowEC2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
    ]
    resources = ["*"]
  }

  # SSM - look up the latest EKS-optimised AMI for each node class
  statement {
    sid     = "AllowSSMAMILookup"
    effect  = "Allow"
    actions = ["ssm:GetParameter"]
    resources = [
      "arn:aws:ssm:${var.aws_region}::parameter/aws/service/*"
    ]
  }

  # EKS - read cluster details to bootstrap nodes correctly
  statement {
    sid     = "AllowEKSDescribe"
    effect  = "Allow"
    actions = ["eks:DescribeCluster"]
    resources = [
      "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${local.cluster_name}"
    ]
  }

  # IAM PassRole - hand the node role to newly launched EC2 instances
  # Scoped to only the Karpenter node role - nothing broader
  statement {
    sid     = "AllowPassNodeRole"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [aws_iam_role.karpenter_node.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # Pricing - evaluate spot instance costs for bin-packing decisions
  statement {
    sid       = "AllowPricingLookup"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }
}

# Inline policy - avoids iam:CreatePolicy (blocked by DMI course deny policy)
resource "aws_iam_role_policy" "karpenter_controller" {
  name   = "${local.name_prefix}-karpenter-controller-policy"
  role   = aws_iam_role.karpenter_controller.id
  policy = data.aws_iam_policy_document.karpenter_controller_permissions.json
}
