#!/bin/bash
set -e

# ============================================
# Azure DevOps Command Wrapper
# ============================================
# This script wraps Azure DevOps CLI commands to enforce:
# 1. Organization is locked to AZURE_DEVOPS_ORG env var
# 2. Project is locked to AZURE_DEVOPS_PROJECT env var
# 3. Repository must be from allowed list (if specified)
#
# Security measures against injection attacks:
# - All variables are properly quoted in expansions
# - Input validation using regex (alphanumeric, dots, dashes, underscores only)
# - Repository names validated against whitelist before use
# - Arguments stored in bash array and safely expanded with "${AZ_ARGS[@]}"
# - printf with %s format specifier used instead of echo for variable output
# - No use of eval, command substitution, or unquoted variable expansion
# - IFS= read -r prevents word splitting during file reading

# ============================================
# Validate environment
# ============================================
if [ -z "$AZURE_DEVOPS_ORG" ]; then
    echo "❌ ERROR: AZURE_DEVOPS_ORG is not set"
    echo "Please configure this in the Dockerfile"
    exit 1
fi

if [ -z "$AZURE_DEVOPS_PROJECT" ]; then
    echo "❌ ERROR: AZURE_DEVOPS_PROJECT is not set"
    echo "Please configure this in the Dockerfile"
    exit 1
fi

# Validate environment variable format (alphanumeric, dash, underscore, dot only)
if [[ ! "$AZURE_DEVOPS_ORG" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "❌ ERROR: AZURE_DEVOPS_ORG contains invalid characters"
    exit 1
fi

if [[ ! "$AZURE_DEVOPS_PROJECT" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "❌ ERROR: AZURE_DEVOPS_PROJECT contains invalid characters"
    exit 1
fi

# ============================================
# Load allowed repositories
# ============================================
ALLOWED_REPOSITORIES_FILE="/etc/allowed-repositories.conf"

if [ ! -f "$ALLOWED_REPOSITORIES_FILE" ]; then
    echo "❌ ERROR: Allowed repositories configuration not found"
    echo ""
    echo "Expected config file at: $ALLOWED_REPOSITORIES_FILE"
    echo ""
    echo "The allowed-repositories.conf file should be included in the Docker image"
    echo "or mounted as read-only. This file defines which Azure DevOps"
    echo "repositories agents are allowed to access."
    exit 1
fi

# Read allowed repositories (ignore comments and empty lines)
ALLOWED_REPOSITORIES=()
while IFS= read -r line; do
    # Skip comments and empty lines
    if [[ ! "$line" =~ ^#.*$ ]] && [[ -n "$line" ]]; then
        # Validate repository name contains only safe characters (alphanumeric, dash, underscore, dot)
        if [[ ! "$line" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            echo "❌ ERROR: Invalid repository name in config: $line"
            echo "Repository names must contain only letters, numbers, dots, dashes, and underscores"
            exit 1
        fi
        ALLOWED_REPOSITORIES+=("$line")
    fi
done < "$ALLOWED_REPOSITORIES_FILE"

if [ ${#ALLOWED_REPOSITORIES[@]} -eq 0 ]; then
    echo "❌ ERROR: No allowed repositories found in $ALLOWED_REPOSITORIES_FILE"
    echo "Please ensure the file contains valid repository names"
    exit 1
fi

# ============================================
# Parse arguments and validate repository
# ============================================
REPOSITORY=""
AZ_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --organization)
            # Block explicit organization parameter
            echo "❌ ERROR: --organization parameter is not allowed"
            echo "Organization is locked to: https://dev.azure.com/\${AZURE_DEVOPS_ORG}"
            exit 1
            ;;
        --project)
            # Block explicit project parameter
            echo "❌ ERROR: --project parameter is not allowed"
            printf "Project is locked to: %s\n" "$AZURE_DEVOPS_PROJECT"
            exit 1
            ;;
        --repository)
            # Capture repository value safely
            if [[ -z "${2:-}" ]]; then
                echo "❌ ERROR: --repository requires a value"
                exit 1
            fi
            REPOSITORY="$2"
            
            # Validate repository name format before checking whitelist
            if [[ ! "$REPOSITORY" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                echo "❌ ERROR: Invalid repository name format"
                echo "Repository names must contain only letters, numbers, dots, dashes, and underscores"
                exit 1
            fi
            
            # Validate repository is in allowed list (string comparison safe with [[ ]])
            REPO_ALLOWED=false
            for allowed_repo in "${ALLOWED_REPOSITORIES[@]}"; do
                if [[ "$REPOSITORY" = "$allowed_repo" ]]; then
                    REPO_ALLOWED=true
                    break
                fi
            done
            
            if [[ "$REPO_ALLOWED" != "true" ]]; then
                printf "❌ ERROR: Repository '%s' is not in the allowed list\n" "$REPOSITORY"
                echo ""
                echo "Allowed repositories:"
                printf "  - %s\n" "${ALLOWED_REPOSITORIES[@]}"
                echo ""
                echo "To see allowed repositories, run: agent-az-devops-list-repositories"
                exit 1
            fi
            
            # Add validated repository to args (safely quoted)
            AZ_ARGS+=("--repository" "$REPOSITORY")
            shift 2
            ;;
        *)
            # Add any other argument safely
            AZ_ARGS+=("$1")
            shift
            ;;
    esac
done

# ============================================
# Execute Azure DevOps CLI command
# ============================================
# Set organization and project via defaults (locked down)
az devops configure --defaults \
    organization="https://dev.azure.com/${AZURE_DEVOPS_ORG}" \
    project="$AZURE_DEVOPS_PROJECT" \
    > /dev/null 2>&1

# Execute the command with remaining args
exec az "${AZ_ARGS[@]}"
