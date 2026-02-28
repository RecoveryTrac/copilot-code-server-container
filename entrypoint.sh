#!/bin/bash
set -e

# ============================================
# Agent Bootstrap Script
# ============================================
# This script runs as an s6 oneshot service during container startup.
# It handles:
# 1. Git configuration validation
# 2. SSH key generation and setup
# 3. Repository cloning with submodules (can take several minutes)
#
# Timeout Settings:
# - Service timeout: 10 minutes (timeout-up file)
# - Global s6 timeout: 10 minutes (S6_CMD_WAIT_FOR_SERVICES_MAXTIME)
# Both must be set high enough for large repository clones with multiple submodules.
# ============================================

# ============================================
# Validate required Git configuration
# ============================================
MISSING_CONFIG=0

if [ -z "$GIT_USERNAME" ]; then
    echo "❌ ERROR: GIT_USERNAME is not set"
    MISSING_CONFIG=1
fi

if [ -z "$GIT_EMAIL" ]; then
    echo "❌ ERROR: GIT_EMAIL is not set"
    MISSING_CONFIG=1
fi

if [ -z "$REPO_URL" ]; then
    echo "❌ ERROR: REPO_URL is not set"
    MISSING_CONFIG=1
fi

if [ -z "$REPO_FOLDER" ]; then
    echo "❌ ERROR: REPO_FOLDER is not set"
    MISSING_CONFIG=1
fi

if [ $MISSING_CONFIG -eq 1 ]; then
    echo ""
    echo "💡 Please set all required environment variables in docker-compose.yml:"
    echo "   - GIT_USERNAME"
    echo "   - GIT_EMAIL"
    echo "   - REPO_URL"
    echo "   - REPO_FOLDER"
    echo ""
    echo "Example:"
    echo "GIT_USERNAME=Your Name"
    echo "GIT_EMAIL=your.email@example.com"
    echo "REPO_URL=git@ssh.dev.azure.com:v3/Org/Project/Repo"
    echo "REPO_FOLDER=MyRepo"
    exit 1
fi

echo "✅ Git configuration validated"

# Set both author and committer to the same values
export GIT_AUTHOR_NAME="$GIT_USERNAME"
export GIT_AUTHOR_EMAIL="$GIT_EMAIL"
export GIT_COMMITTER_NAME="$GIT_USERNAME"
export GIT_COMMITTER_EMAIL="$GIT_EMAIL"

# ============================================
# SSH key auto-generation
# ============================================
SSH_DIR="/home/agent/.ssh"
SSH_KEY="$SSH_DIR/id_rsa"

if [ ! -f "$SSH_KEY" ]; then
    echo "🔑 SSH keys not found. Generating new SSH key pair..."
    mkdir -p "$SSH_DIR"
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N "" -C "${GIT_EMAIL}"
    chmod 700 "$SSH_DIR"
    chmod 600 "$SSH_KEY"
    chmod 644 "$SSH_KEY.pub"
    echo "✅ SSH key pair generated at $SSH_KEY"
    echo ""
    echo "📋 Your public key (add this to Azure DevOps):"
    echo "================================================"
    cat "$SSH_KEY.pub"
    echo "================================================"
    echo ""
else
    echo "✅ SSH keys already exist at $SSH_KEY"
fi

# ============================================
# Configure git
# ============================================
git config --global user.name "$GIT_USERNAME"
git config --global user.email "$GIT_EMAIL"
echo "✅ Git configured: $GIT_USERNAME <$GIT_EMAIL>"

# ============================================
# Configure SSH for Azure DevOps
# ============================================
# StrictHostKeyChecking accept-new: Accept new host keys on first connection
#   but reject changed keys (security + convenience balance)
# LogLevel ERROR: Suppress "Permanently added..." warnings during submodule clones
mkdir -p "$SSH_DIR"
cat > "$SSH_DIR/config" <<EOF
Host ssh.dev.azure.com
    HostName ssh.dev.azure.com
    User git
    IdentityFile $SSH_KEY
    StrictHostKeyChecking accept-new
    LogLevel ERROR
EOF
chmod 600 "$SSH_DIR/config"
echo "✅ SSH configured for Azure DevOps"

# ============================================
# Clone or access repository
# ============================================
WORKSPACE_DIR="/home/agent/workspace"
REPO_PATH="$WORKSPACE_DIR/$REPO_FOLDER"

if [ ! -d "$REPO_PATH" ]; then
    echo "📦 Cloning repository (this may take several minutes): $REPO_URL"
    echo "   into: $REPO_PATH"
    echo "   Note: Cloning main repo + submodules..."
    
    if ! git clone --recurse-submodules --progress "$REPO_URL" "$REPO_PATH"; then
        echo ""
        echo "❌ ERROR: Failed to clone repository (see error above)"
        echo ""
        echo "💡 This might be because your SSH key is not added to Azure DevOps."
        echo "   If so, add your public key:"
        echo "================================================"
        cat "$SSH_KEY.pub"
        echo "================================================"
        echo ""
        echo "📖 Instructions for adding SSH key to Azure DevOps:"
        echo "   https://learn.microsoft.com/en-us/azure/devops/repos/git/use-ssh-keys-to-authenticate?view=azure-devops#step-2-add-the-public-key-to-azure-devops"
        echo ""
        echo "   After adding the key, restart the container."
        echo ""
        echo "   If the SSH key is already configured, see the error message above for more details."
        exit 1
    fi
    
    echo "✅ Repository cloned successfully"
    
    # ============================================
    # Update all repos to latest commit on their main branches
    # ============================================
    echo "🔄 Updating all repositories to latest commits..."
    
    CONFIG_FILE="/etc/repo-mappings.json"
    
    # Verify config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        echo ""
        echo "❌ ERROR: Repository mappings configuration not found at $CONFIG_FILE"
        echo ""
        echo "💡 The container requires this configuration file to determine the main branch"
        echo "   for each repository (root and submodules)."
        echo ""
        echo "   Expected format:"
        echo "   {"
        echo "     \"repoMainBranches\": {"
        echo "       \".\": \"main\","
        echo "       \"./Services\": \"develop\""
        echo "     }"
        echo "   }"
        echo ""
        echo "   This file should be copied during Docker build. Check your Dockerfile."
        exit 1
    fi
    
    cd "$REPO_PATH"
    
    # Verify jq is available
    if ! command -v jq &> /dev/null; then
        echo ""
        echo "❌ ERROR: 'jq' command not found"
        echo ""
        echo "💡 The 'jq' utility is required to parse repository mappings from $CONFIG_FILE"
        echo ""
        echo "   This is a container build issue. The Dockerfile should install jq:"
        echo "   RUN apt-get update && apt-get install -y jq"
        echo ""
        echo "   Rebuild the container image to include jq."
        exit 1
    fi
    
    # Load repo-to-main-branch mapping
    declare -A REPO_MAIN_BRANCHES
    if ! MAPPINGS=$(jq -r '.repoMainBranches | to_entries | .[] | "\(.key)=\(.value)"' "$CONFIG_FILE" 2>&1); then
        echo ""
        echo "❌ ERROR: Failed to parse $CONFIG_FILE"
        echo ""
        echo "💡 The jq command failed to parse the JSON configuration file."
        echo ""
        echo "   Error details:"
        echo "$MAPPINGS" | sed 's/^/   /'
        echo ""
        echo "   Verify the file contains valid JSON in this format:"
        echo "   {"
        echo "     \"repoMainBranches\": {"
        echo "       \".\": \"main\","
        echo "       \"./Services\": \"develop\""
        echo "     }"
        echo "   }"
        exit 1
    fi
    
    while IFS="=" read -r key value; do
        REPO_MAIN_BRANCHES["$key"]="$value"
    done <<< "$MAPPINGS"
    
    # Verify we have mappings
    if [ ${#REPO_MAIN_BRANCHES[@]} -eq 0 ]; then
        echo ""
        echo "❌ ERROR: No repository mappings found in $CONFIG_FILE"
        echo ""
        echo "💡 The configuration file exists but contains no repoMainBranches entries."
        echo "   Check the file format and ensure it has at least one repository mapping."
        exit 1
    fi
    
    # Update each repository
    for REPO_KEY in "${!REPO_MAIN_BRANCHES[@]}"; do
        MAIN_BRANCH="${REPO_MAIN_BRANCHES[$REPO_KEY]}"
        
        if [ "$REPO_KEY" = "." ]; then
            # Root repository
            REPO_NAME="root"
            REPO_DIR="$REPO_PATH"
        else
            # Submodule (e.g., "./Services" -> "Services")
            REPO_NAME=$(basename "$REPO_KEY")
            REPO_DIR="$REPO_PATH/$REPO_NAME"
        fi
        
        # Verify directory is a valid git repository
        # Note: Submodules have a .git FILE (not directory) pointing to parent's .git/modules/
        if [ ! -e "$REPO_DIR/.git" ]; then
            echo ""
            echo "❌ ERROR: Repository '$REPO_NAME' is not a valid git repository"
            echo "   Expected location: $REPO_DIR"
            echo ""
            echo "💡 This repository was just cloned with --recurse-submodules, so all"
            echo "   repositories listed in $CONFIG_FILE should exist as valid git repos."
            echo ""
            echo "   Possible causes:"
            echo "   1. The repository path in repo-mappings.json is incorrect"
            echo "   2. The submodule failed to initialize during clone"
            echo "   3. The repository path doesn't match the actual submodule location"
            echo ""
            echo "   Verify that '$REPO_KEY' matches an actual repository in your setup."
            exit 1
        fi
        
        echo "   📍 Updating $REPO_NAME to latest $MAIN_BRANCH..."
        
        cd "$REPO_DIR"
        
        # Fetch latest
        if ! git fetch origin 2>&1; then
            echo ""
            echo "❌ ERROR: Failed to fetch from origin for repository '$REPO_NAME'"
            echo "   Repository: $REPO_DIR"
            echo "   Branch: $MAIN_BRANCH"
            echo ""
            echo "💡 The git fetch command failed. This could be due to:"
            echo "   1. Network connectivity issues"
            echo "   2. SSH authentication problems"
            echo "   3. Invalid remote configuration"
            echo ""
            echo "   Check the error message above for details."
            exit 1
        fi
        
        # Checkout main branch
        if ! git checkout "$MAIN_BRANCH" 2>&1; then
            echo ""
            echo "❌ ERROR: Failed to checkout branch '$MAIN_BRANCH' for repository '$REPO_NAME'"
            echo "   Repository: $REPO_DIR"
            echo ""
            echo "💡 The branch specified in $CONFIG_FILE may not exist."
            echo ""
            echo "   Verify that:"
            echo "   1. The branch name '$MAIN_BRANCH' is correct"
            echo "   2. The branch exists in the remote repository"
            echo "   3. The mapping in repo-mappings.json is accurate"
            echo ""
            echo "   Check the error message above for details."
            exit 1
        fi
        
        # Pull latest
        if ! git pull origin "$MAIN_BRANCH" 2>&1; then
            echo ""
            echo "❌ ERROR: Failed to pull latest from '$MAIN_BRANCH' for repository '$REPO_NAME'"
            echo "   Repository: $REPO_DIR"
            echo "   Branch: $MAIN_BRANCH"
            echo ""
            echo "💡 The git pull command failed. This could be due to:"
            echo "   1. Network connectivity issues"
            echo "   2. Merge conflicts (unlikely on fresh clone)"
            echo "   3. Remote branch configuration issues"
            echo ""
            echo "   Check the error message above for details."
            exit 1
        fi
        
        echo "   ✅ $REPO_NAME updated to latest $MAIN_BRANCH"
    done
    
    cd "$REPO_PATH"
    echo "✅ All repositories updated to latest commits"
else
    echo "✅ Repository already exists at $REPO_PATH, proceeding!"
fi

cd "$REPO_PATH"
echo "📁 Working directory: $(pwd)"

# Execute whatever command was passed (CMD or override)
exec "$@"
