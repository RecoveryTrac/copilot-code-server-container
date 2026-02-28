#!/bin/bash
set -e

# ============================================
# List Allowed Azure DevOps Repositories
# ============================================
# Simple script to list which repositories agents can access

ALLOWED_REPOSITORIES_FILE="/etc/allowed-repositories.conf"

if [ ! -f "$ALLOWED_REPOSITORIES_FILE" ]; then
    echo "❌ ERROR: Allowed repositories configuration not found at $ALLOWED_REPOSITORIES_FILE"
    exit 1
fi

echo "Allowed Azure DevOps Repositories:"
echo ""

# Read and display allowed repositories (ignore comments and empty lines)
while IFS= read -r line; do
    # Skip comments and empty lines
    if [[ ! "$line" =~ ^#.*$ ]] && [[ -n "$line" ]]; then
        echo "  - $line"
    fi
done < "$ALLOWED_REPOSITORIES_FILE"
