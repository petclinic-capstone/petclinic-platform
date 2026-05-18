#!/usr/bin/env bash
# =============================================================================
# scripts/bootstrap-phase2.sh
#
# Phase 2 — Kubernetes Core Controllers Bootstrap
#
# Installs (in dependency order):
#   1. EBS CSI Driver     — EKS managed add-on, provides PersistentVolumes
#   2. AWS LB Controller  — provisions the ALB when Ingress objects are applied
#   3. External Secrets   — syncs AWS Secrets Manager → Kubernetes Secrets
#   4. External-DNS       — creates Route53 records from Ingress annotations
#   5. ArgoCD             — GitOps engine; deploys PetClinic microservices
#
# Prerequisites:
#   - kubectl configured for petclinic-dev  (aws eks update-kubeconfig)
#   - helm 3.x installed
#   - aws CLI configured with profile petclinic-infra-paul
#
# Usage:
#   bash scripts/bootstrap-phase2.sh
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
ACCOUNT_ID="482352877891"
REGION="us-east-1"
CLUSTER_NAME="petclinic-dev"
DOMAIN="demo.lulamistack.co"
PROFILE="petclinic-infra-paul"

# IRSA Role ARNs — all provisioned by terraform/modules/iam
LBC_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/petclinic-dev-lb-controller-role"
ESO_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/petclinic-dev-eso-role"
EBS_CSI_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/petclinic-dev-ebs-csi-role"
EXT_DNS_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/petclinic-dev-external-dns-role"

# ── Colours ───────────────────────────────────────────────────────────────────
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'

phase()   { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}\n"; }
ok()      { echo -e "${GREEN}  ✔  $*${RESET}"; }
info()    { echo -e "${CYAN}  ℹ  $*${RESET}"; }
warn()    { echo -e "${YELLOW}  ⚠  $*${RESET}"; }
die()     { echo -e "${RED}  ✖  $*${RESET}"; exit 1; }

# ── Prereq check ──────────────────────────────────────────────────────────────
for cmd in aws kubectl helm; do
  command -v "$cmd" &>/dev/null || die "Missing required tool: $cmd"
done
ok "Prerequisites: aws, kubectl, helm all present"

# Confirm we're talking to the right cluster
CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "none")
info "Current kubectl context: ${CURRENT_CTX}"
if ! echo "$CURRENT_CTX" | grep -q "$CLUSTER_NAME"; then
  warn "Context does not contain '${CLUSTER_NAME}' — are you sure this is the right cluster?"
  read -r -p "  Continue anyway? [y/N] " confirm
  [[ "${confirm,,}" == "y" ]] || { info "Aborted."; exit 0; }
fi

# ── Fetch VPC ID (needed by LBC) ──────────────────────────────────────────────
info "Fetching VPC ID for cluster ${CLUSTER_NAME}..."
VPC_ID=$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --profile "$PROFILE" \
  --filters "Name=tag:Name,Values=petclinic-dev-vpc" \
  --query 'Vpcs[0].VpcId' \
  --output text 2>/dev/null || echo "")

if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  die "Could not find VPC tagged 'petclinic-dev-vpc'. Check your AWS credentials and region."
fi
ok "VPC ID: ${VPC_ID}"

# ── Add Helm repos ────────────────────────────────────────────────────────────
phase "Updating Helm repos"
helm repo add eks                https://aws.github.io/eks-charts           2>/dev/null || true
helm repo add external-secrets   https://charts.external-secrets.io         2>/dev/null || true
helm repo add external-dns       https://kubernetes-sigs.github.io/external-dns/ 2>/dev/null || true
helm repo add argo               https://argoproj.github.io/argo-helm       2>/dev/null || true
helm repo update
ok "Helm repos up to date"

# =============================================================================
# 1. EBS CSI DRIVER  (EKS managed add-on)
# =============================================================================
phase "1/5  EBS CSI Driver"

ADDON_STATUS=$(aws eks describe-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name aws-ebs-csi-driver \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'addon.status' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "$ADDON_STATUS" == "ACTIVE" ]]; then
  ok "EBS CSI add-on already ACTIVE — skipping"
else
  info "Installing EBS CSI add-on (status: ${ADDON_STATUS})..."
  aws eks create-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name aws-ebs-csi-driver \
    --service-account-role-arn "$EBS_CSI_ROLE_ARN" \
    --resolve-conflicts OVERWRITE \
    --region "$REGION" \
    --profile "$PROFILE" \
    --output text > /dev/null

  info "Waiting for EBS CSI add-on to become ACTIVE..."
  aws eks wait addon-active \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name aws-ebs-csi-driver \
    --region "$REGION" \
    --profile "$PROFILE"
  ok "EBS CSI add-on is ACTIVE"
fi

# =============================================================================
# 2. AWS LOAD BALANCER CONTROLLER
# =============================================================================
phase "2/5  AWS Load Balancer Controller"

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${LBC_ROLE_ARN}" \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}" \
  --wait \
  --timeout 5m

ok "AWS Load Balancer Controller installed"

# Verify controller pods are running
info "LBC pods:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# =============================================================================
# 3. EXTERNAL SECRETS OPERATOR
# =============================================================================
phase "3/5  External Secrets Operator"

kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --set installCRDs=true \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-secrets-sa \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${ESO_ROLE_ARN}" \
  --wait \
  --timeout 5m

ok "External Secrets Operator installed"

# Create ClusterSecretStore — tells ESO how to auth with AWS Secrets Manager
info "Applying ClusterSecretStore..."
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${REGION}
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
EOF
ok "ClusterSecretStore 'aws-secrets-manager' created"

# =============================================================================
# 4. EXTERNAL-DNS
# =============================================================================
phase "4/5  External-DNS"

kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns \
  --set provider=aws \
  --set "domainFilters[0]=${DOMAIN}" \
  --set txtOwnerId="${CLUSTER_NAME}" \
  --set policy=sync \
  --set aws.region="${REGION}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-dns \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${EXT_DNS_ROLE_ARN}" \
  --wait \
  --timeout 5m

ok "External-DNS installed"

# =============================================================================
# 5. ARGOCD
# =============================================================================
phase "5/5  ArgoCD"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=ClusterIP \
  --set configs.params."server\.insecure"=true \
  --wait \
  --timeout 10m

ok "ArgoCD installed"

# Print initial admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "not yet available")

# =============================================================================
# SUMMARY
# =============================================================================
phase "Bootstrap Complete"

echo -e "${BOLD}  Installed controllers:${RESET}"
echo -e "  ${GREEN}✔${RESET}  EBS CSI Driver           (kube-system)"
echo -e "  ${GREEN}✔${RESET}  AWS Load Balancer Ctrl   (kube-system)"
echo -e "  ${GREEN}✔${RESET}  External Secrets Op      (external-secrets)"
echo -e "  ${GREEN}✔${RESET}  External-DNS             (external-dns)"
echo -e "  ${GREEN}✔${RESET}  ArgoCD                   (argocd)"
echo ""
echo -e "${BOLD}  ArgoCD admin password:${RESET} ${ARGOCD_PASSWORD}"
echo ""
echo -e "${BOLD}  Access ArgoCD UI (port-forward):${RESET}"
echo -e "    kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo -e "    then open: http://localhost:8080"
echo -e "    username: admin"
echo ""
echo -e "${BOLD}  Next step:${RESET} Run the Phase 3 ArgoCD app bootstrap"
echo -e "    bash scripts/bootstrap-phase3.sh"
echo ""

kubectl get pods -A | grep -v "Running\|Completed" | grep -v "^NAMESPACE" && \
  warn "Some pods are not yet Running — give it 60s and recheck with: kubectl get pods -A" || \
  ok "All pods Running"
