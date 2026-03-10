#!/usr/bin/env bash
# =============================================================================
# scripts/bootstrap-team.sh
# DevOps Unlocked — New Team Bootstrap
#
# Provisions the prerequisites for a new squad to use Terraform:
# - S3 state bucket (if not already exists)
# - DynamoDB lock table (if not already exists)
# - IAM role for the team's CI/CD pipeline
# - SSM parameters granting read access to foundation outputs
#
# Run once per new squad onboarding. Idempotent — safe to re-run.
#
# Usage:
#   ./bootstrap-team.sh --account-id 123456789012 --region eu-west-1 --team compute-squad
#
# Prerequisites:
#   - AWS credentials with AdministratorAccess (or scoped equivalent)
#   - aws CLI >= 2.13
# =============================================================================

set -euo pipefail

ACCOUNT_ID=""
REGION=""
TEAM_NAME=""

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

usage() {
  echo "Usage: $0 --account-id <AWS_ACCOUNT_ID> --region <AWS_REGION> --team <TEAM_NAME>"
  echo ""
  echo "Options:"
  echo "  --account-id    AWS account ID"
  echo "  --region        AWS region"
  echo "  --team          Team/squad name (e.g., compute-squad, data-squad)"
  echo "  --help          Show this help"
  exit 2
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --account-id) ACCOUNT_ID="$2"; shift 2 ;;
    --region)     REGION="$2"; shift 2 ;;
    --team)       TEAM_NAME="$2"; shift 2 ;;
    --help)       usage ;;
    *)            echo "Unknown argument: $1"; usage ;;
  esac
done

if [[ -z "$ACCOUNT_ID" || -z "$REGION" || -z "$TEAM_NAME" ]]; then
  echo "ERROR: --account-id, --region, and --team are all required."
  usage
fi

# ACTION REQUIRED: Update these to match your organisation's naming conventions
STATE_BUCKET="your-org-terraform-state-prod"     # ACTION REQUIRED: Replace
LOCK_TABLE="terraform-state-locks"
STATE_KEY="teams/${TEAM_NAME}/terraform.tfstate"
CI_ROLE_NAME="${TEAM_NAME}-terraform-ci"

# -----------------------------------------------------------------------------
# Auth check
# -----------------------------------------------------------------------------

echo "============================================================"
echo "  TEAM BOOTSTRAP: $TEAM_NAME"
echo "  Account: $ACCOUNT_ID | Region: $REGION"
echo "============================================================"
echo ""

echo "==> Verifying AWS authentication..."

CALLER=$(aws sts get-caller-identity --output json)
ACTUAL_ACCOUNT=$(echo "$CALLER" | jq -r '.Account')

if [[ "$ACTUAL_ACCOUNT" != "$ACCOUNT_ID" ]]; then
  echo "ERROR: Authenticated account ($ACTUAL_ACCOUNT) != --account-id ($ACCOUNT_ID)"
  exit 2
fi

echo "    Authenticated as: $(echo "$CALLER" | jq -r '.Arn')"

# -----------------------------------------------------------------------------
# Step 1: S3 state bucket
# -----------------------------------------------------------------------------

echo ""
echo "==> Step 1: Ensuring Terraform state S3 bucket exists..."

if aws s3api head-bucket --bucket "$STATE_BUCKET" --region "$REGION" 2>/dev/null; then
  echo "    Bucket already exists: s3://$STATE_BUCKET — skipping creation."
else
  echo "    Creating bucket: s3://$STATE_BUCKET"
  aws s3api create-bucket \
    --bucket "$STATE_BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"

  echo "    Enabling versioning..."
  aws s3api put-bucket-versioning \
    --bucket "$STATE_BUCKET" \
    --versioning-configuration Status=Enabled

  echo "    Blocking public access..."
  aws s3api put-public-access-block \
    --bucket "$STATE_BUCKET" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  echo "    Bucket created and secured: s3://$STATE_BUCKET"
fi

# -----------------------------------------------------------------------------
# Step 2: DynamoDB lock table
# -----------------------------------------------------------------------------

echo ""
echo "==> Step 2: Ensuring DynamoDB lock table exists..."

if aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$REGION" &>/dev/null; then
  echo "    Lock table already exists: $LOCK_TABLE — skipping creation."
else
  echo "    Creating DynamoDB table: $LOCK_TABLE"
  aws dynamodb create-table \
    --table-name "$LOCK_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"

  echo "    Waiting for table to be active..."
  aws dynamodb wait table-exists --table-name "$LOCK_TABLE" --region "$REGION"
  echo "    Lock table ready: $LOCK_TABLE"
fi

# -----------------------------------------------------------------------------
# Step 3: IAM role for CI/CD pipeline
# -----------------------------------------------------------------------------

echo ""
echo "==> Step 3: Creating IAM role for ${TEAM_NAME} CI/CD pipeline..."

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

# ACTION REQUIRED: Update the trust policy principal to match your CI/CD system
# For GitHub Actions: "token.actions.githubusercontent.com"
# For GitLab: your GitLab instance ARN
# For Jenkins: the Jenkins server IAM role ARN

if aws iam get-role --role-name "$CI_ROLE_NAME" &>/dev/null; then
  echo "    IAM role already exists: $CI_ROLE_NAME — skipping creation."
else
  aws iam create-role \
    --role-name "$CI_ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --description "CI/CD Terraform role for ${TEAM_NAME}" \
    --tags "Key=managed_by,Value=terraform" "Key=squad,Value=${TEAM_NAME}" \
    --region "$REGION"

  echo "    Created IAM role: $CI_ROLE_NAME"
fi

# Attach a scoped inline policy granting access to this team's state prefix only
STATE_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "StateAccess",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::${STATE_BUCKET}/${STATE_KEY}"
    },
    {
      "Sid": "StateBucketList",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${STATE_BUCKET}"
    },
    {
      "Sid": "LockTableAccess",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${LOCK_TABLE}"
    },
    {
      "Sid": "FoundationSSMRead",
      "Effect": "Allow",
      "Action": ["ssm:GetParameter", "ssm:GetParametersByPath"],
      "Resource": "arn:aws:ssm:${REGION}:${ACCOUNT_ID}:parameter/platform/foundation/*"
    }
  ]
}
EOF
)

aws iam put-role-policy \
  --role-name "$CI_ROLE_NAME" \
  --policy-name "${TEAM_NAME}-terraform-state-policy" \
  --policy-document "$STATE_POLICY"

echo "    IAM policy attached: scoped to teams/${TEAM_NAME}/ state prefix"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "============================================================"
echo "  BOOTSTRAP COMPLETE: $TEAM_NAME"
echo "============================================================"
echo ""
echo "  State bucket:  s3://${STATE_BUCKET}"
echo "  State key:     ${STATE_KEY}"
echo "  Lock table:    ${LOCK_TABLE}"
echo "  CI IAM role:   arn:aws:iam::${ACCOUNT_ID}:role/${CI_ROLE_NAME}"
echo ""
echo "  Next steps:"
echo "  1. Update the trust policy on $CI_ROLE_NAME to match your CI system"
echo "  2. Copy terraform/teams/compute-squad/ as a template for this team"
echo "  3. Update backend.tf with the state key: ${STATE_KEY}"
echo "  4. Run 'terraform init' in the new team directory"
echo "============================================================"
