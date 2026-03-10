#!/usr/bin/env bash
# =============================================================================
# scripts/check-module-versions.sh
# DevOps Unlocked — Module Version Drift Detector
#
# Scans all team configuration directories and reports which module
# versions each squad is running. Flags teams that are more than one
# major version behind the current stable release.
#
# Usage:
#   ./check-module-versions.sh
#
# Run this in CI weekly or as a pre-merge gate.
# Exit codes:
#   0 — All teams on acceptable versions
#   1 — One or more teams are critically out of date
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEAMS_DIR="${REPO_ROOT}/terraform/teams"

# -----------------------------------------------------------------------------
# Current stable versions — update these when releasing new module versions
# ACTION REQUIRED: Update these version strings when you publish new module releases
# -----------------------------------------------------------------------------
declare -A CURRENT_VERSIONS=(
  ["s3-secure"]="2.1.0"
  ["rds-postgres"]="1.4.2"
  ["app-cluster"]="3.2.1"
  ["eks-compliant"]="1.0.0"
)

declare -A MAX_LAG_MAJOR=(
  ["s3-secure"]="1"
  ["rds-postgres"]="1"
  ["app-cluster"]="1"
  ["eks-compliant"]="1"
)

DRIFT_FOUND=0

# -----------------------------------------------------------------------------
# Helper: extract major version number
# -----------------------------------------------------------------------------
major_version() {
  echo "$1" | cut -d'.' -f1
}

# -----------------------------------------------------------------------------
# Helper: check if version is acceptably current
# -----------------------------------------------------------------------------
version_acceptable() {
  local current_major=$1
  local found_major=$2
  local max_lag=$3

  if (( current_major - found_major > max_lag )); then
    return 1
  fi
  return 0
}

# -----------------------------------------------------------------------------
# Scan team directories
# -----------------------------------------------------------------------------

echo "============================================================"
echo "  MODULE VERSION DRIFT REPORT"
echo "  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "============================================================"
echo ""

echo "Current stable versions:"
for module in "${!CURRENT_VERSIONS[@]}"; do
  echo "  $module: ${CURRENT_VERSIONS[$module]}"
done
echo ""

if [[ ! -d "$TEAMS_DIR" ]]; then
  echo "ERROR: Teams directory not found: $TEAMS_DIR"
  exit 1
fi

echo "Scanning team configurations..."
echo ""

for team_dir in "${TEAMS_DIR}"/*/; do
  team_name=$(basename "$team_dir")
  echo "  Squad: $team_name"

  # Find all main.tf files in the team directory
  while IFS= read -r tf_file; do
    # Extract module source and version references
    # Looks for patterns like: version = "x.y.z" near module blocks
    while IFS= read -r version_line; do
      # Portable version extraction (works on Linux and MacOS)
      version=$(echo "$version_line" | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/' || true)
      
      # Validate that we actually got a version string
      if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        continue
      fi

      # Try to identify which module this version belongs to
      # by looking at the source line above it or nearby
      for module in "${!CURRENT_VERSIONS[@]}"; do
        if grep -q "$module" "$tf_file" 2>/dev/null; then
          found_major=$(major_version "$version")
          current_major=$(major_version "${CURRENT_VERSIONS[$module]}")
          max_lag="${MAX_LAG_MAJOR[$module]}"

          if version_acceptable "$current_major" "$found_major" "$max_lag"; then
            echo "    [OK]   $module: $version (current: ${CURRENT_VERSIONS[$module]})"
          else
            echo "    [WARN] $module: $version — CRITICALLY BEHIND (current: ${CURRENT_VERSIONS[$module]}, max lag: $max_lag major version)"
            DRIFT_FOUND=1
          fi
        fi
      done

    done < <(grep 'version\s*=' "$tf_file" 2>/dev/null || true)

  done < <(find "$team_dir" -name "*.tf" -type f 2>/dev/null)

  echo ""
done

echo "============================================================"

if [[ "$DRIFT_FOUND" -eq 0 ]]; then
  echo "  STATUS: PASS — All teams within acceptable version range."
else
  echo "  STATUS: FAIL — Module version drift detected."
  echo ""
  echo "  Remediation:"
  echo "    1. Open upgrade PRs for flagged teams"
  echo "    2. Review module changelog for breaking changes"
  echo "    3. Test in staging before applying to prod"
  echo "    4. Update version pin in team main.tf"
fi

echo "============================================================"

exit $DRIFT_FOUND
