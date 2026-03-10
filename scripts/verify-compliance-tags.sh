#!/usr/bin/env bash
# =============================================================================
# scripts/verify-compliance-tags.sh
# DevOps Unlocked — Compliance Tag Verification
#
# Scans AWS resources in a given account and region and checks that all
# mandatory compliance tags are present and non-empty.
#
# Required tags: managed_by, compliance_scope, data_classification,
#                cost_centre, squad, environment
#
# Usage:
#   ./verify-compliance-tags.sh --account-id 123456789012 --region eu-west-1
#
# Exit codes:
#   0 — All resources compliant
#   1 — Non-compliant resources found (details printed to stdout)
#   2 — Script error (missing dependencies, auth failure)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

MANDATORY_TAGS=("managed_by" "compliance_scope" "data_classification" "cost_centre" "squad" "environment")
NON_COMPLIANT_COUNT=0
ACCOUNT_ID=""
REGION=""

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

usage() {
  echo "Usage: $0 --account-id <AWS_ACCOUNT_ID> --region <AWS_REGION>"
  echo ""
  echo "Options:"
  echo "  --account-id    AWS account ID to scan"
  echo "  --region        AWS region to scan"
  echo "  --help          Show this help message"
  exit 2
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --account-id) ACCOUNT_ID="$2"; shift 2 ;;
    --region)     REGION="$2"; shift 2 ;;
    --help)       usage ;;
    *)            echo "Unknown argument: $1"; usage ;;
  esac
done

if [[ -z "$ACCOUNT_ID" || -z "$REGION" ]]; then
  echo "ERROR: --account-id and --region are required."
  usage
fi

# -----------------------------------------------------------------------------
# Dependency checks
# -----------------------------------------------------------------------------

echo "==> Checking dependencies..."

for cmd in aws jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: Required command '$cmd' not found. Install it and retry."
    exit 2
  fi
done

echo "    aws CLI: $(aws --version 2>&1 | head -1)"
echo "    jq:      $(jq --version)"

# -----------------------------------------------------------------------------
# Auth verification
# -----------------------------------------------------------------------------

echo ""
echo "==> Verifying AWS authentication..."

CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>&1) || {
  echo "ERROR: AWS authentication failed. Configure credentials and retry."
  exit 2
}

ACTUAL_ACCOUNT=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
if [[ "$ACTUAL_ACCOUNT" != "$ACCOUNT_ID" ]]; then
  echo "ERROR: Authenticated account ($ACTUAL_ACCOUNT) does not match --account-id ($ACCOUNT_ID)."
  echo "       Configure the correct AWS credentials and retry."
  exit 2
fi

echo "    Account:  $ACTUAL_ACCOUNT"
echo "    Identity: $(echo "$CALLER_IDENTITY" | jq -r '.Arn')"
echo "    Region:   $REGION"

# -----------------------------------------------------------------------------
# Helper: check tags on a resource
# -----------------------------------------------------------------------------

check_tags() {
  local resource_arn="$1"
  local resource_type="$2"
  local tags_json="$3"

  local missing_tags=()

  for tag_key in "${MANDATORY_TAGS[@]}"; do
    tag_value=$(echo "$tags_json" | jq -r --arg key "$tag_key" '.[] | select(.Key == $key) | .Value // empty')
    if [[ -z "$tag_value" ]]; then
      missing_tags+=("$tag_key")
    fi
  done

  if [[ ${#missing_tags[@]} -gt 0 ]]; then
    echo "  NON-COMPLIANT [$resource_type]"
    echo "    ARN:          $resource_arn"
    echo "    Missing tags: ${missing_tags[*]}"
    echo ""
    NON_COMPLIANT_COUNT=$((NON_COMPLIANT_COUNT + 1))
  fi
}

# -----------------------------------------------------------------------------
# Scan S3 Buckets
# -----------------------------------------------------------------------------

echo ""
echo "==> Scanning S3 buckets..."

S3_BUCKETS=$(aws s3api list-buckets \
  --query 'Buckets[].Name' \
  --output json \
  --region "$REGION" 2>/dev/null || echo "[]")

BUCKET_COUNT=$(echo "$S3_BUCKETS" | jq 'length')
echo "    Found $BUCKET_COUNT buckets"

while IFS= read -r bucket; do
  TAGS=$(aws s3api get-bucket-tagging \
    --bucket "$bucket" \
    --query 'TagSet' \
    --output json \
    --region "$REGION" 2>/dev/null || echo "[]")
  check_tags "arn:aws:s3:::${bucket}" "S3 Bucket" "$TAGS"
done < <(echo "$S3_BUCKETS" | jq -r '.[]')

# -----------------------------------------------------------------------------
# Scan RDS Instances
# -----------------------------------------------------------------------------

echo "==> Scanning RDS instances..."

RDS_INSTANCES=$(aws rds describe-db-instances \
  --query 'DBInstances[].DBInstanceArn' \
  --output json \
  --region "$REGION" 2>/dev/null || echo "[]")

RDS_COUNT=$(echo "$RDS_INSTANCES" | jq 'length')
echo "    Found $RDS_COUNT RDS instances"

while IFS= read -r arn; do
  TAGS=$(aws rds list-tags-for-resource \
    --resource-name "$arn" \
    --query 'TagList' \
    --output json \
    --region "$REGION" 2>/dev/null || echo "[]")
  check_tags "$arn" "RDS Instance" "$TAGS"
done < <(echo "$RDS_INSTANCES" | jq -r '.[]')

# -----------------------------------------------------------------------------
# Results
# -----------------------------------------------------------------------------

echo ""
echo "============================================================"
echo "  COMPLIANCE TAG VERIFICATION RESULTS"
echo "  Account: $ACCOUNT_ID | Region: $REGION"
echo "============================================================"

if [[ "$NON_COMPLIANT_COUNT" -eq 0 ]]; then
  echo "  STATUS: PASS — All scanned resources have mandatory tags."
  echo "============================================================"
  exit 0
else
  echo "  STATUS: FAIL — $NON_COMPLIANT_COUNT resource(s) missing mandatory tags."
  echo ""
  echo "  Mandatory tags required on all resources:"
  for tag in "${MANDATORY_TAGS[@]}"; do
    echo "    - $tag"
  done
  echo ""
  echo "  Remediation: Ensure resources are deployed via DevOps Unlocked"
  echo "  atomic modules, which inject mandatory tags automatically."
  echo "============================================================"
  exit 1
fi
