#!/usr/bin/env bash
# =============================================================================
# scripts/cost-control.sh
#
# PetClinic 7-Hour Auto-Destroy Cost Controller
#
# HOW IT WORKS
#   1. Use --apply instead of running terraform apply directly.
#      The script runs terraform apply then writes the current Unix timestamp
#      to SSM Parameter Store (/petclinic/dev/cost-control/apply-timestamp).
#
#   2. A cron job runs --check every 30 minutes.
#      If 7 hours have elapsed since apply, a 60-second prompt appears.
#      No response → terraform destroy runs automatically.
#      Responding "KEEP" resets the 7-hour clock.
#
#   3. The interactive menu lets you manually stop/start resources via the
#      cost-control Lambda without destroying everything, or trigger a full
#      destroy immediately.
#
# SETUP (run once after terraform apply):
#   bash scripts/cost-control.sh --apply          # first apply + start clock
#   bash scripts/cost-control.sh --setup-cron     # install 30-min cron check
#
# MANUAL RUN:
#   bash scripts/cost-control.sh                  # interactive menu
#   bash scripts/cost-control.sh --check          # check timer now (used by cron)
#   bash scripts/cost-control.sh --apply          # re-apply + reset clock
#   bash scripts/cost-control.sh --status         # show resource + timer status
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-petclinic-infra-paul}"
TERRAFORM_DIR="$(cd "$(dirname "$0")/../terraform/environments/dev" && pwd)"
LOG_FILE="$HOME/.petclinic-cost-control.log"
LAMBDA_NAME="petclinic-dev-cost-control"
SSM_PARAM="/petclinic/dev/cost-control/apply-timestamp"
AUTO_DESTROY_HOURS=7
PROMPT_TIMEOUT_SECS=60

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
info()    { echo -e "${CYAN}  ℹ  $*${RESET}"; }
success() { echo -e "${GREEN}  ✔  $*${RESET}"; }
warn()    { echo -e "${YELLOW}  ⚠  $*${RESET}"; }
error()   { echo -e "${RED}  ✖  $*${RESET}"; }
header()  { echo -e "\n${BOLD}${BLUE}$*${RESET}\n"; }

check_deps() {
  local missing=0
  for cmd in aws terraform python3; do
    if ! command -v "$cmd" &>/dev/null; then
      error "Required command not found: $cmd"
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || exit 1
}

aws_cmd() {
  aws --region "$AWS_REGION" --profile "$AWS_PROFILE" "$@"
}

# ── SSM timestamp helpers ─────────────────────────────────────────────────────
write_apply_timestamp() {
  local ts
  ts=$(date +%s)
  aws_cmd ssm put-parameter \
    --name "$SSM_PARAM" \
    --value "$ts" \
    --type "String" \
    --overwrite \
    --description "Unix timestamp of last terraform apply — used by 7-hour auto-destroy" \
    > /dev/null
  success "Apply timestamp recorded in SSM: $(date -d "@${ts}" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -r "${ts}" '+%Y-%m-%d %H:%M:%S %Z')"
  log "TIMESTAMP: apply recorded at epoch ${ts}"
}

read_apply_timestamp() {
  aws_cmd ssm get-parameter \
    --name "$SSM_PARAM" \
    --query "Parameter.Value" \
    --output text 2>/dev/null || echo "0"
}

elapsed_hours() {
  local apply_ts="$1"
  local now
  now=$(date +%s)
  echo $(( (now - apply_ts) / 3600 ))
}

elapsed_minutes() {
  local apply_ts="$1"
  local now
  now=$(date +%s)
  echo $(( (now - apply_ts) / 60 ))
}

# ── Invoke the cost-control Lambda ───────────────────────────────────────────
invoke_lambda() {
  local action="$1"
  local payload="{\"action\":\"${action}\"}"
  local response_file
  response_file=$(mktemp /tmp/cost-control-XXXXXX.json)

  info "Invoking Lambda: ${LAMBDA_NAME} → action=${action}"

  aws_cmd lambda invoke \
    --function-name "$LAMBDA_NAME" \
    --payload "$payload" \
    --cli-binary-format raw-in-base64-out \
    "$response_file" \
    --query 'StatusCode' \
    --output text 2>/dev/null

  echo ""
  python3 -m json.tool "$response_file" 2>/dev/null || cat "$response_file"
  rm -f "$response_file"
}

# ── Show resource + timer status ──────────────────────────────────────────────
show_status() {
  header "Resource & Timer Status"

  local apply_ts
  apply_ts=$(read_apply_timestamp)

  if [[ "$apply_ts" == "0" ]]; then
    warn "No apply timestamp found in SSM. Run --apply to start the clock."
  else
    local elapsed_m elapsed_h apply_time remaining_m
    elapsed_m=$(elapsed_minutes "$apply_ts")
    elapsed_h=$(elapsed_hours "$apply_ts")
    apply_time=$(date -d "@${apply_ts}" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null \
                 || date -r "${apply_ts}" '+%Y-%m-%d %H:%M:%S %Z')
    remaining_m=$(( AUTO_DESTROY_HOURS * 60 - elapsed_m ))

    info "Apply time      : ${apply_time}"
    info "Elapsed         : ${elapsed_h}h ${elapsed_m}m"
    if [[ $remaining_m -le 0 ]]; then
      warn "Auto-destroy window EXPIRED ${remaining_m#-} min ago — destroy will run at next --check"
    else
      info "Auto-destroy in : ${remaining_m} min (at ${AUTO_DESTROY_HOURS}h mark)"
    fi
  fi

  echo ""
  invoke_lambda "status"
}

# ── Terraform apply wrapper ───────────────────────────────────────────────────
do_apply() {
  header "Terraform Apply + Start 7-Hour Clock"
  info "Running terraform apply in: ${TERRAFORM_DIR}"
  echo ""

  cd "$TERRAFORM_DIR"
  terraform init -reconfigure
  terraform apply

  echo ""
  write_apply_timestamp
  success "Infrastructure is up. Auto-destroy in ${AUTO_DESTROY_HOURS} hours."
  info "Install the auto-destroy cron now if not already set up:"
  info "  bash $(realpath "$0") --setup-cron"
  log "ACTION: apply completed and timestamp recorded"
}

# ── 7-hour auto-destroy check (run by cron) ───────────────────────────────────
do_check() {
  local apply_ts
  apply_ts=$(read_apply_timestamp)

  if [[ "$apply_ts" == "0" ]]; then
    log "CHECK: no apply timestamp — skipping"
    exit 0
  fi

  local elapsed_h
  elapsed_h=$(elapsed_hours "$apply_ts")

  if [[ $elapsed_h -lt $AUTO_DESTROY_HOURS ]]; then
    log "CHECK: ${elapsed_h}h elapsed — within ${AUTO_DESTROY_HOURS}h window, no action"
    exit 0
  fi

  # 7 hours have passed — prompt with timeout
  log "CHECK: ${elapsed_h}h elapsed — prompting for keep-alive or destroy"

  # If running non-interactively (cron with no terminal), skip prompt and destroy
  if ! tty -s 2>/dev/null; then
    log "AUTO-DESTROY: non-interactive session — destroying automatically"
    _run_destroy "non-interactive 7-hour timeout"
    exit 0
  fi

  echo ""
  echo -e "${BOLD}${RED}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${RED}║  ⚠  7-HOUR AUTO-DESTROY TRIGGERED                           ║${RESET}"
  echo -e "${BOLD}${RED}║                                                              ║${RESET}"
  echo -e "${BOLD}${RED}║  Infrastructure has been running for ${elapsed_h}h.                   ║${RESET}"
  echo -e "${BOLD}${RED}║  Type KEEP within ${PROMPT_TIMEOUT_SECS} seconds to reset the clock.        ║${RESET}"
  echo -e "${BOLD}${RED}║  No response → terraform destroy runs automatically.         ║${RESET}"
  echo -e "${BOLD}${RED}╚══════════════════════════════════════════════════════════════╝${RESET}"
  echo ""

  local user_input=""
  if read -r -t "$PROMPT_TIMEOUT_SECS" -p "  Keep infrastructure alive? Type KEEP: " user_input 2>/dev/null; then
    if [[ "${user_input^^}" == "KEEP" ]]; then
      write_apply_timestamp   # reset the 7-hour clock
      success "Clock reset. Next auto-destroy check in ${AUTO_DESTROY_HOURS} hours."
      log "ACTION: keep-alive confirmed by user — clock reset"
      exit 0
    else
      warn "Response '${user_input}' not recognised — proceeding with destroy."
      log "ACTION: unrecognised input '${user_input}' — destroying"
    fi
  else
    warn "No response within ${PROMPT_TIMEOUT_SECS} seconds — proceeding with auto-destroy."
    log "ACTION: prompt timed out — destroying"
  fi

  _run_destroy "7-hour timeout"
}

# ── Shared destroy logic (pre-cleanup + terraform destroy) ────────────────────
_run_destroy() {
  local reason="${1:-manual}"
  log "DESTROY: starting — reason: ${reason}"

  header "Running Pre-Destroy Cleanup (LBs, SGs, ENIs)"

  VPC_ID=$(aws_cmd ec2 describe-vpcs \
    --filters "Name=tag:Project,Values=petclinic" "Name=tag:Environment,Values=dev" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")

  if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
    # Delete ALBs/NLBs in the VPC
    for arn in $(aws_cmd elbv2 describe-load-balancers \
      --query "LoadBalancers[?VpcId=='${VPC_ID}'].LoadBalancerArn" \
      --output text 2>/dev/null); do
      warn "Deleting ALB/NLB: $arn"
      aws_cmd elbv2 delete-load-balancer --load-balancer-arn "$arn" 2>/dev/null || true
    done

    # Delete classic ELBs
    for lb in $(aws_cmd elb describe-load-balancers \
      --query "LoadBalancerDescriptions[?VPCId=='${VPC_ID}'].LoadBalancerName" \
      --output text 2>/dev/null); do
      warn "Deleting classic ELB: $lb"
      aws_cmd elb delete-load-balancer --load-balancer-name "$lb" 2>/dev/null || true
    done

    sleep 20

    # Delete orphaned k8s-managed security groups
    for sg in $(aws_cmd ec2 describe-security-groups \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query "SecurityGroups[?starts_with(GroupName,'k8s-elb-')].GroupId" \
      --output text 2>/dev/null); do
      warn "Deleting orphaned SG: $sg"
      aws_cmd ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
    done

    # Detach and delete dangling ENIs
    for eni in $(aws_cmd ec2 describe-network-interfaces \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'NetworkInterfaces[*].NetworkInterfaceId' \
      --output text 2>/dev/null); do
      local attach_id
      attach_id=$(aws_cmd ec2 describe-network-interfaces \
        --network-interface-ids "$eni" \
        --query 'NetworkInterfaces[0].Attachment.AttachmentId' \
        --output text 2>/dev/null || echo "None")
      if [[ "$attach_id" != "None" && -n "$attach_id" ]]; then
        aws_cmd ec2 detach-network-interface --attachment-id "$attach_id" --force 2>/dev/null || true
        sleep 3
      fi
      aws_cmd ec2 delete-network-interface --network-interface-id "$eni" 2>/dev/null || true
    done
  fi

  info "Running terraform destroy..."
  cd "$TERRAFORM_DIR"
  terraform destroy -auto-approve

  # Clear the SSM timestamp so --check knows there is nothing running
  aws_cmd ssm delete-parameter --name "$SSM_PARAM" 2>/dev/null || true

  success "Destroy complete."
  log "DESTROY: completed — reason: ${reason}"
}

# ── Manual stop (Lambda) ──────────────────────────────────────────────────────
do_stop() {
  header "Stop Resources (RDS + Scale Nodes to 0)"
  warn "Pods will terminate. RDS data is preserved. EC2 billing stops."
  echo ""
  read -r -p "  Confirm stop? [y/N] " confirm
  if [[ "${confirm,,}" != "y" ]]; then info "Stop cancelled."; return; fi
  invoke_lambda "stop"
  success "Stop sent. RDS stops in ~2 min. Nodes terminate shortly."
  log "ACTION: stop — user confirmed"
}

# ── Manual start (Lambda) ─────────────────────────────────────────────────────
do_start() {
  header "Start Resources (RDS + Restore Nodes)"
  info "Scales nodes back to 2 and starts RDS."
  echo ""
  read -r -p "  Confirm start? [y/N] " confirm
  if [[ "${confirm,,}" != "y" ]]; then info "Start cancelled."; return; fi
  invoke_lambda "start"
  success "Start sent. RDS available in ~5 min. Nodes join in ~3 min."
  log "ACTION: start — user confirmed"
}

# ── Manual full destroy ───────────────────────────────────────────────────────
do_shutdown() {
  header "Full Infrastructure Shutdown"
  warn "This destroys EVERYTHING: EKS, RDS, VPC, ECR, IAM roles."
  warn "All data and workloads will be permanently deleted."
  echo ""
  read -r -p "  Type 'DESTROY' to confirm: " confirm
  if [[ "$confirm" != "DESTROY" ]]; then info "Shutdown cancelled."; return; fi
  _run_destroy "manual shutdown"
}

# ── Setup cron ────────────────────────────────────────────────────────────────
setup_cron() {
  local script_path
  script_path="$(realpath "$0")"
  # Run every 30 minutes — ensures auto-destroy fires within 30 min of the 7h mark
  local cron_cmd="*/30 * * * * AWS_REGION=${AWS_REGION} AWS_PROFILE=${AWS_PROFILE} bash ${script_path} --check >> ${LOG_FILE} 2>&1"

  header "Installing 30-Minute Auto-Destroy Check"
  info "Cron entry:"
  echo ""
  echo "  $cron_cmd"
  echo ""
  read -r -p "  Add to crontab? [y/N] " confirm
  if [[ "${confirm,,}" == "y" ]]; then
    (crontab -l 2>/dev/null | grep -v "cost-control"; echo "$cron_cmd") | crontab -
    success "Cron installed. Auto-destroy will trigger ${AUTO_DESTROY_HOURS}h after your last --apply."
    info "View logs: tail -f ${LOG_FILE}"
    info "View crontab: crontab -l"
  else
    info "Cron not installed. Run --check manually or schedule it yourself."
  fi
}

# ── Interactive menu ──────────────────────────────────────────────────────────
main_menu() {
  clear
  echo ""
  echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║     PetClinic AWS Cost Control               ║${RESET}"
  echo -e "${BOLD}${BLUE}║     $(date '+%a %d %b %Y  %H:%M %Z')              ║${RESET}"
  echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════╝${RESET}"
  echo ""

  show_status

  echo ""
  echo -e "${BOLD}  What would you like to do?${RESET}"
  echo ""
  echo -e "  ${GREEN}1)${RESET} ${BOLD}Keep Alive${RESET}    — reset 7-hour clock, do nothing else"
  echo -e "  ${YELLOW}2)${RESET} ${BOLD}Stop${RESET}          — pause RDS + scale nodes to 0 (saves credits)"
  echo -e "  ${CYAN}3)${RESET} ${BOLD}Start${RESET}         — resume RDS + restore nodes (after a stop)"
  echo -e "  ${RED}4)${RESET} ${BOLD}Shutdown${RESET}      — terraform destroy everything now"
  echo -e "  ${BLUE}5)${RESET} ${BOLD}Status only${RESET}   — show status and exit"
  echo ""
  read -r -p "  Enter choice [1-5]: " choice

  case "$choice" in
    1)
      write_apply_timestamp
      success "7-hour clock reset. Next auto-destroy check in ${AUTO_DESTROY_HOURS} hours."
      log "ACTION: keep_alive — clock reset"
      ;;
    2) do_stop     ;;
    3) do_start    ;;
    4) do_shutdown ;;
    5) info "Exiting." ;;
    *)
      warn "Invalid choice. Keeping resources alive."
      log "ACTION: invalid input '${choice}' — no action"
      ;;
  esac
}

# ── Entry point ───────────────────────────────────────────────────────────────
case "${1:-}" in
  --apply)      check_deps; do_apply       ;;
  --check)      aws_cmd ssm get-parameter --name "$SSM_PARAM" &>/dev/null && do_check || { log "CHECK: no timestamp — skipping"; exit 0; } ;;
  --setup-cron) setup_cron               ;;
  --status)     show_status              ;;
  "")           check_deps; main_menu    ;;
  *)
    error "Unknown option: ${1}"
    echo "Usage: $0 [--apply | --check | --setup-cron | --status]"
    exit 1
    ;;
esac
