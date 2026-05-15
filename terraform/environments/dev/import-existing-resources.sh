#!/bin/bash
# =============================================================================
# import-existing-resources.sh
#
# Run this from terraform/environments/dev when AWS resources already exist
# but are missing from Terraform state (EntityAlreadyExists errors on apply).
#
# Usage:
#   cd ~/petclinic-platform/terraform/environments/dev
#   chmod +x import-existing-resources.sh
#   ./import-existing-resources.sh
# =============================================================================

set -e  # stop on first error

CLUSTER_NAME="petclinic-dev"
REGION="us-east-1"
ACCOUNT_ID="482352877891"

echo ""
echo "============================================="
echo " Terraform Import — EKS + IAM + Related"
echo "============================================="
echo ""

# -----------------------------------------------------------------------------
# 1. Look up resource IDs that can't be derived from names alone
# -----------------------------------------------------------------------------

echo "[1/3] Looking up dynamic resource IDs from AWS..."

# OIDC provider ARN — filter by EKS issuer hostname
OIDC_ARN=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn,'oidc.eks')].Arn" \
  --output text 2>/dev/null | head -1)

# Launch template ID — created with name prefix petclinic-dev-eks-node-
LT_ID=$(aws ec2 describe-launch-templates \
  --region "$REGION" \
  --filters "Name=launch-template-name,Values=${CLUSTER_NAME}-eks-node-*" \
  --query "LaunchTemplates[0].LaunchTemplateId" \
  --output text 2>/dev/null)

echo "  OIDC ARN       : ${OIDC_ARN:-NOT FOUND}"
echo "  Launch Tmpl ID : ${LT_ID:-NOT FOUND}"
echo ""

# -----------------------------------------------------------------------------
# 2. Import EKS module resources
# -----------------------------------------------------------------------------

echo "[2/3] Importing module.eks resources..."

# IAM roles
terraform import module.eks.aws_iam_role.cluster \
  "${CLUSTER_NAME}-eks-cluster-role"

terraform import module.eks.aws_iam_role.node \
  "${CLUSTER_NAME}-eks-node-role"

# IAM policy attachments  (format: role-name/policy-arn)
terraform import module.eks.aws_iam_role_policy_attachment.cluster_policy \
  "${CLUSTER_NAME}-eks-cluster-role/arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"

terraform import module.eks.aws_iam_role_policy_attachment.node_worker_policy \
  "${CLUSTER_NAME}-eks-node-role/arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"

terraform import module.eks.aws_iam_role_policy_attachment.node_cni_policy \
  "${CLUSTER_NAME}-eks-node-role/arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"

terraform import module.eks.aws_iam_role_policy_attachment.node_registry_policy \
  "${CLUSTER_NAME}-eks-node-role/arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"

# EKS cluster
terraform import module.eks.aws_eks_cluster.this \
  "$CLUSTER_NAME"

# Launch template — needs the actual ID
if [[ -n "$LT_ID" && "$LT_ID" != "None" ]]; then
  terraform import module.eks.aws_launch_template.node "$LT_ID"
else
  echo "  WARNING: Launch template not found — skipping. Check manually."
fi

# Node group  (format: cluster-name:nodegroup-name)
terraform import module.eks.aws_eks_node_group.main \
  "${CLUSTER_NAME}:${CLUSTER_NAME}-nodes"

# OIDC provider
if [[ -n "$OIDC_ARN" && "$OIDC_ARN" != "None" ]]; then
  terraform import module.eks.aws_iam_openid_connect_provider.eks "$OIDC_ARN"
else
  echo "  WARNING: OIDC provider not found — skipping. Check manually."
fi

# -----------------------------------------------------------------------------
# 3. Verify state is clean
# -----------------------------------------------------------------------------

echo ""
echo "[3/3] Running terraform plan to check for remaining drift..."
echo "      (expect 14 new resources for the 7 EKS access entries — nothing else)"
echo ""
terraform plan

echo ""
echo "Done. If plan shows only the 14 eks-access additions, run: terraform apply"
