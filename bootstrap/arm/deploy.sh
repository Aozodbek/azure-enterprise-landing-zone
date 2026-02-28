#!/usr/bin/env bash


# Usage:
#   ./deploy.sh [--env <dev|prod>] [--subscription <id>] [--dry-run]
#
# Prerequisites:
#   - Azure CLI >= 2.50.0   (az --version)
#   - Logged-in principal must have Owner or Contributor + User Access Admin
#     on the target subscription
#   - jq (for output parsing)

set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/main.json"
ENV="dev"
SUBSCRIPTION_ID=""
DRY_RUN=false
DEPLOYMENT_NAME="tfstate-bootstrap-$(date -u +%Y%m%dT%H%M%SZ)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}==> $*${RESET}"; }


usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --env          <dev|prod>      Deployment environment (default: dev)
  --subscription <id>            Azure subscription ID (default: current CLI context)
  --dry-run                      Validate template only, do not deploy
  -h, --help                     Show this help

Examples:
  ./deploy.sh --env dev
  ./deploy.sh --env prod --subscription 00000000-0000-0000-0000-000000000000
  ./deploy.sh --env prod --dry-run
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)          ENV="$2";          shift 2 ;;
    --subscription) SUBSCRIPTION_ID="$2"; shift 2 ;;
    --dry-run)      DRY_RUN=true;      shift ;;
    -h|--help)      usage ;;
    *)              error "Unknown argument: $1" ;;
  esac
done

PARAMS_FILE="${SCRIPT_DIR}/parameters/${ENV}.parameters.json"
[[ -f "$PARAMS_FILE" ]] || error "Parameters file not found: ${PARAMS_FILE}"


header "Preflight Checks"

command -v az  &>/dev/null || error "Azure CLI not found. Install: https://aka.ms/installazureclimacos"
command -v jq  &>/dev/null || error "jq not found. Install: brew install jq"

AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
info "Azure CLI version: ${AZ_VERSION}"

CURRENT_ACCOUNT=$(az account show 2>/dev/null) || error "Not logged in. Run: az login"
CURRENT_SUB=$(echo "$CURRENT_ACCOUNT" | jq -r '.id')
CURRENT_SUB_NAME=$(echo "$CURRENT_ACCOUNT" | jq -r '.name')
CURRENT_TENANT=$(echo "$CURRENT_ACCOUNT" | jq -r '.tenantId')
CURRENT_USER=$(echo "$CURRENT_ACCOUNT" | jq -r '.user.name')

# Set subscription if provided, else use current context
if [[ -n "$SUBSCRIPTION_ID" ]]; then
  info "Setting subscription: ${SUBSCRIPTION_ID}"
  az account set --subscription "$SUBSCRIPTION_ID"
  CURRENT_SUB="$SUBSCRIPTION_ID"
  CURRENT_SUB_NAME=$(az account show --query 'name' -o tsv)
fi

echo
echo -e "  ${BOLD}Subscription:${RESET} ${CURRENT_SUB_NAME} (${CURRENT_SUB})"
echo -e "  ${BOLD}Tenant:${RESET}       ${CURRENT_TENANT}"
echo -e "  ${BOLD}Principal:${RESET}    ${CURRENT_USER}"
echo -e "  ${BOLD}Environment:${RESET}  ${ENV}"
echo -e "  ${BOLD}Parameters:${RESET}   ${PARAMS_FILE}"
echo -e "  ${BOLD}Template:${RESET}     ${TEMPLATE_FILE}"
echo -e "  ${BOLD}Dry run:${RESET}      ${DRY_RUN}"
echo

# Require explicit confirmation for prod non-dry-run
if [[ "$ENV" == "prod" && "$DRY_RUN" == "false" ]]; then
  warn "You are about to deploy PRODUCTION bootstrap resources."
  read -r -p "  Type 'yes-prod' to confirm: " confirm
  [[ "$confirm" == "yes-prod" ]] || error "Aborted by user."
fi


# Determine ARM location from parameters file

LOCATION=$(jq -r '.parameters.location.value' "$PARAMS_FILE")
[[ "$LOCATION" != "null" && -n "$LOCATION" ]] || error "Could not resolve 'location' from ${PARAMS_FILE}"
info "Deployment location: ${LOCATION}"


# Template validation (always run)

header "Validating ARM Template"

VALIDATE_OUTPUT=$(az deployment sub validate \
  --location "$LOCATION" \
  --name "${DEPLOYMENT_NAME}-validate" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "@${PARAMS_FILE}" \
  --subscription "$CURRENT_SUB" \
  --output json 2>&1) || {
    echo "$VALIDATE_OUTPUT" | jq '.error' 2>/dev/null || echo "$VALIDATE_OUTPUT"
    error "Template validation failed."
  }

success "Template is valid."

if [[ "$DRY_RUN" == "true" ]]; then
  header "Preflight (What-If Analysis)"

  az deployment sub what-if \
    --location "$LOCATION" \
    --name "${DEPLOYMENT_NAME}-whatif" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@${PARAMS_FILE}" \
    --subscription "$CURRENT_SUB" \
    --result-format FullResourcePayloads

  info "Dry run complete. No resources were created."
  exit 0
fi


# Deploy

header "Deploying Bootstrap Resources"
info "Deployment name: ${DEPLOYMENT_NAME}"
info "This may take 2-5 minutes..."

DEPLOY_OUTPUT=$(az deployment sub create \
  --location "$LOCATION" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "@${PARAMS_FILE}" \
  --subscription "$CURRENT_SUB" \
  --output json) || {
    error "Deployment failed. Check Azure Portal > Deployments for details."
  }


# Extract and display outputs

header "Deployment Complete"

STORAGE_ACCOUNT=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.storageAccountName.value')
RESOURCE_GROUP=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.resourceGroupName.value')
BLOB_ENDPOINT=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.primaryEndpointBlob.value')
PRINCIPAL_ID=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.systemAssignedPrincipalId.value')
BACKEND_CONFIG=$(echo "$DEPLOY_OUTPUT" | jq -r '.properties.outputs.backendConfig.value')

success "Resource group:      ${RESOURCE_GROUP}"
success "Storage account:     ${STORAGE_ACCOUNT}"
success "Blob endpoint:       ${BLOB_ENDPOINT}"
success "System identity:     ${PRINCIPAL_ID}"


# Print backend.tf snippet

header "Add to backend.tf"
BACKEND_CONTAINER="tfstate"

cat <<EOF

  backend "azurerm" {
    resource_group_name  = "${RESOURCE_GROUP}"
    storage_account_name = "${STORAGE_ACCOUNT}"
    container_name       = "${BACKEND_CONTAINER}"
    key                  = "${ENV}/terraform.tfstate"

    # Authentication: ensure ARM_CLIENT_ID / ARM_CLIENT_SECRET (or OIDC) are set,
    # or use use_oidc = true for GitHub Actions federated credentials.
    # State locking via Azure Blob lease — prevents concurrent modifications.
    # No DynamoDB equivalent needed (unlike S3 backend).
  }

EOF


# Write .tfbackend file for use with terraform init -backend-config

BACKEND_FILE="${SCRIPT_DIR}/../../${ENV}.tfbackend"
cat > "$BACKEND_FILE" <<EOF
resource_group_name  = "${RESOURCE_GROUP}"
storage_account_name = "${STORAGE_ACCOUNT}"
container_name       = "${BACKEND_CONTAINER}"
key                  = "${ENV}/terraform.tfstate"
EOF

success "Backend config written to: ${BACKEND_FILE}"
info   "  terraform init -backend-config=${ENV}.tfbackend"


# Optional: verify storage account accessibility

header "Verifying Storage Account"

if az storage account show \
     --name "$STORAGE_ACCOUNT" \
     --resource-group "$RESOURCE_GROUP" \
     --query 'name' -o tsv &>/dev/null; then
  success "Storage account is accessible."

  # List containers
  CONTAINERS=$(az storage container list \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --query '[].name' -o tsv 2>/dev/null || echo "(requires Storage Blob Data Reader role)")

  info "Containers: ${CONTAINERS}"
else
  warn "Storage account not accessible from this principal (network ACLs may be active)."
fi

echo
success "Bootstrap complete. You can now run: terraform init -backend-config=${ENV}.tfbackend"
