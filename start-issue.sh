#!/bin/bash
set -e

# ============================================
# Parse arguments
# ============================================
ISSUE_NUMBER=""
AGENT_NAME=""

show_help() {
    cat << EOF
Usage: start-issue <issue-number> [options]

Prepare workspace for working on an Azure DevOps work item by:
  1. Fetching work item details from Azure DevOps
  2. Creating/checking out deterministic branch names
  3. Prompting for which repositories to actively work on
  4. Spinning up a GitHub Copilot agent in yolo mode

Arguments:
  <issue-number>          Azure DevOps work item ID (required)

Options:
  --agent <name>          Name of the copilot agent to spin up (optional, defaults to 'agent')
  --help                  Show this help message

Examples:
  start-issue 1234
  start-issue 1234 --agent my-agent

EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            ;;
        --agent)
            AGENT_NAME="$2"
            shift 2
            ;;
        -*)
            echo "❌ ERROR: Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [ -z "$ISSUE_NUMBER" ]; then
                ISSUE_NUMBER="$1"
            else
                echo "❌ ERROR: Unexpected argument: $1"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# ============================================
# Validate parameters
# ============================================
if [ -z "$ISSUE_NUMBER" ]; then
    echo "❌ ERROR: Issue number is required"
    echo "Usage: start-issue <issue-number> [--agent <agent-name>]"
    echo "Use --help for more information"
    exit 1
fi

# Validate issue number is a positive integer
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ ERROR: Issue number must be a positive integer"
    echo "Provided: $ISSUE_NUMBER"
    exit 1
fi

if [ "$ISSUE_NUMBER" -le 0 ]; then
    echo "❌ ERROR: Issue number must be greater than 0"
    echo "Provided: $ISSUE_NUMBER"
    exit 1
fi

# Default agent name if not specified
if [ -z "$AGENT_NAME" ]; then
    AGENT_NAME="agent"
    echo "ℹ️ No agent specified, using default: $AGENT_NAME"
fi

# ============================================
# Validate required environment variables
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

# ============================================
# Check Azure CLI login status
# ============================================
echo "🔐 Checking Azure CLI login status..."
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure CLI"
    echo "🔑 Starting Azure CLI login flow..."
    az login
    echo "✅ Successfully logged in to Azure CLI"
else
    echo "✅ Already logged in to Azure CLI"
fi

# ============================================
# Fetch issue data from Azure DevOps
# ============================================
echo "📋 Fetching issue #${ISSUE_NUMBER} from Azure DevOps..."

# Fetch the work item using the agent wrapper (org and project are locked via env vars)
WORK_ITEM=$(agent-az-devops boards work-item show --id "$ISSUE_NUMBER" --output json 2>&1)

if [ -z "$WORK_ITEM" ]; then
    echo "❌ ERROR: Could not find issue #${ISSUE_NUMBER}"
    echo "Please verify the issue number and your permissions"
    exit 1
fi

# Extract the title
ISSUE_TITLE=$(echo "$WORK_ITEM" | jq -r '.fields["System.Title"]')

if [ -z "$ISSUE_TITLE" ] || [ "$ISSUE_TITLE" == "null" ]; then
    echo "❌ ERROR: Could not extract issue title"
    exit 1
fi

echo "✅ Found issue: $ISSUE_TITLE"

# ============================================
# Generate deterministic branch name
# ============================================
# Convert title to lowercase and replace spaces/special chars with hyphens
SANITIZED_TITLE=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

# Build branch name starting with issue number
BRANCH_NAME="${ISSUE_NUMBER}"
CURRENT_LENGTH=${#BRANCH_NAME}
MAX_LENGTH=24

# Add words from title until we hit the char limit (don't truncate words)
IFS='-' read -ra WORDS <<< "$SANITIZED_TITLE"
for WORD in "${WORDS[@]}"; do
    # Check if adding this word (plus hyphen) would exceed limit
    WORD_WITH_HYPHEN="-${WORD}"
    NEW_LENGTH=$((CURRENT_LENGTH + ${#WORD_WITH_HYPHEN}))
    
    if [ $NEW_LENGTH -le $MAX_LENGTH ]; then
        BRANCH_NAME="${BRANCH_NAME}${WORD_WITH_HYPHEN}"
        CURRENT_LENGTH=$NEW_LENGTH
    else
        break
    fi
done

echo "🌿 Branch name: $BRANCH_NAME"

# ============================================
# Load repo-to-main-branch mapping
# ============================================
CONFIG_FILE="/etc/repo-mappings.json"

declare -A REPO_MAIN_BRANCHES

# Verify config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ ERROR: Repository mappings configuration not found"
    echo ""
    echo "Expected config file at: $CONFIG_FILE"
    echo ""
    echo "The repo-mappings.json file should be included in the Docker image"
    echo "or mounted as read-only in docker-compose.yml. This file defines"
    echo "which repositories exist and their main branch names."
    exit 1
fi

echo "📋 Loading repo mappings from: $CONFIG_FILE"

# Parse config file
while IFS="=" read -r key value; do
    REPO_MAIN_BRANCHES["$key"]="$value"
done < <(jq -r '.repoMainBranches | to_entries | .[] | "\(.key)=\(.value)"' "$CONFIG_FILE")

# Validate that we loaded at least one repository mapping
if [ ${#REPO_MAIN_BRANCHES[@]} -eq 0 ]; then
    echo "❌ ERROR: No repository mappings found in $CONFIG_FILE"
    echo "Please ensure the file contains valid repository configuration"
    exit 1
fi

# Validate that root repository is configured
if [ -z "${REPO_MAIN_BRANCHES[.]}" ]; then
    echo "❌ ERROR: Root repository '.' is not defined in $CONFIG_FILE"
    echo "The config must include a mapping for '.' (the root workspace directory)"
    exit 1
fi

# ============================================
# Validate we're in a git repository
# ============================================
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ ERROR: Current directory is not a git repository"
    echo "Current directory: $(pwd)"
    echo ""
    echo "This script must be run from the root of your git workspace."
    echo "Please verify REPO_FOLDER is correctly configured in docker-compose.yml"
    exit 1
fi

# ============================================
# Check if we should prompt for repo selection
# ============================================
ROOT_MAIN_BRANCH="${REPO_MAIN_BRANCHES[.]}"
CURRENT_ROOT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Array to store which repos are selected for work
declare -A SELECTED_REPOS

# Check if we're on the main branch, the target branch, or scratchpad for this issue
SCRATCHPAD_BRANCH="scratchpad/${ISSUE_NUMBER}"

if [ "$CURRENT_ROOT_BRANCH" != "$ROOT_MAIN_BRANCH" ] && \
   [ "$CURRENT_ROOT_BRANCH" != "$BRANCH_NAME" ] && \
   [ "$CURRENT_ROOT_BRANCH" != "$SCRATCHPAD_BRANCH" ]; then
    # We're on some other issue's branch
    echo ""
    echo "⚠️  WARNING: Root repository is currently on branch: $CURRENT_ROOT_BRANCH"
    echo "   This appears to be a different issue."
    echo ""
    echo "   Are you sure you want to switch to issue #${ISSUE_NUMBER}?"
    echo ""
    
    if gum confirm "Switch to issue #${ISSUE_NUMBER}?"; then
        echo ""
        echo "✅ Confirmed - switching to issue #${ISSUE_NUMBER}"
    else
        echo ""
        echo "❌ Cancelled - staying on current branch"
        exit 0
    fi
fi

if [ "$CURRENT_ROOT_BRANCH" = "$ROOT_MAIN_BRANCH" ]; then
    echo ""
    echo "🔍 Detected root repository is on main branch ($ROOT_MAIN_BRANCH)"
    echo "📝 Please select which repositories you want to work on for issue #${ISSUE_NUMBER}:"
    echo ""
    
    # Build options for gum choose
    REPO_OPTIONS=()
    for REPO_PATH in "${!REPO_MAIN_BRANCHES[@]}"; do
        REPO_OPTIONS+=("$REPO_PATH")
    done
    
    # Sort options for consistent display (put root first)
    IFS=$'\n' SORTED_OPTIONS=($(sort <<<"${REPO_OPTIONS[*]}" | grep -E '^\.$' ; sort <<<"${REPO_OPTIONS[*]}" | grep -v -E '^\.$'))
    unset IFS
    
    # Use gum to prompt for repo selection
    SELECTED=$(gum choose --no-limit --height=10 "${SORTED_OPTIONS[@]}")
    
    # Store selected repos in associative array
    while IFS= read -r repo; do
        SELECTED_REPOS["$repo"]=1
    done <<< "$SELECTED"
    
    echo ""
    echo "✅ Selected repositories:"
    for repo in "${!SELECTED_REPOS[@]}"; do
        echo "   - $repo"
    done
else
    echo ""
    echo "✅ Root repository is not on main branch ($CURRENT_ROOT_BRANCH), skipping repo selection"
    echo "   All repositories will use existing branches"
    
    # Mark all repos as "selected" (will use existing branches)
    for REPO_PATH in "${!REPO_MAIN_BRANCHES[@]}"; do
        SELECTED_REPOS["$REPO_PATH"]=1
    done
fi

# ============================================
# Process each repository
# ============================================
for REPO_PATH in "${!REPO_MAIN_BRANCHES[@]}"; do
    MAIN_BRANCH="${REPO_MAIN_BRANCHES[$REPO_PATH]}"
    
    # Determine which branch to use for this repo
    if [ -n "${SELECTED_REPOS[$REPO_PATH]}" ]; then
        TARGET_BRANCH="$BRANCH_NAME"
        BRANCH_TYPE="work"
    else
        TARGET_BRANCH="scratchpad/${ISSUE_NUMBER}"
        BRANCH_TYPE="scratchpad"
    fi
    
    echo ""
    echo "📦 Processing repository: $REPO_PATH"
    echo "   Main branch: $MAIN_BRANCH"
    echo "   Target branch: $TARGET_BRANCH ($BRANCH_TYPE)"
    
    # Validate repository path exists
    if [ ! -d "$REPO_PATH" ]; then
        echo "   ❌ ERROR: Repository path does not exist: $REPO_PATH"
        echo ""
        echo "This path is defined in $CONFIG_FILE but does not exist in the workspace."
        echo "Please verify:"
        echo "  1. The repository path in $CONFIG_FILE is correct"
        echo "  2. All submodules are properly initialized and updated"
        echo "  3. REPO_FOLDER is correctly mounted in docker-compose.yml"
        exit 1
    fi
    
    # Navigate to repo (with error handling)
    if ! cd "$REPO_PATH" 2>/dev/null; then
        echo "   ❌ ERROR: Cannot change directory to: $REPO_PATH"
        echo "Please verify file system permissions and mounts in docker-compose.yml"
        exit 1
    fi
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD 2>/dev/null; then
        echo "   ❌ ERROR: Repository has uncommitted changes"
        echo "   Please commit or stash your changes before switching issues"
        echo "   Repository: $(pwd)"
        exit 1
    fi
    
    # Check if branch exists locally or remotely
    BRANCH_EXISTS_LOCAL=$(git branch --list "$TARGET_BRANCH" | wc -l)
    BRANCH_EXISTS_REMOTE=$(git ls-remote --heads origin "$TARGET_BRANCH" | wc -l)
    
    if [ "$BRANCH_EXISTS_LOCAL" -eq 0 ] && [ "$BRANCH_EXISTS_REMOTE" -eq 0 ]; then
        # Branch doesn't exist - create it from main branch
        echo "   🆕 Branch does not exist, creating from $MAIN_BRANCH..."
        
        # Fetch latest
        if ! git fetch origin 2>&1; then
            echo "   ❌ ERROR: Failed to fetch from remote origin"
            echo "Please verify git remote configuration and network connectivity"
            exit 1
        fi
        
        # Checkout main branch
        if ! git checkout "$MAIN_BRANCH" 2>&1; then
            echo "   ❌ ERROR: Failed to checkout main branch: $MAIN_BRANCH"
            echo "Please verify the branch name in $CONFIG_FILE is correct"
            exit 1
        fi
        
        if ! git pull origin "$MAIN_BRANCH" 2>&1; then
            echo "   ❌ ERROR: Failed to pull latest changes from: $MAIN_BRANCH"
            echo "Please resolve any conflicts or remote issues"
            exit 1
        fi
        
        # Create new branch
        if ! git checkout -b "$TARGET_BRANCH" 2>&1; then
            echo "   ❌ ERROR: Failed to create new branch: $TARGET_BRANCH"
            exit 1
        fi
        echo "   ✅ Created new local branch: $TARGET_BRANCH"
        
        # Create draft PR for work branches only (not scratchpad)
        if [ "$BRANCH_TYPE" = "work" ]; then
            echo "   📝 Creating draft pull request..."
            
            # Determine Azure DevOps repository name
            if [ "$REPO_PATH" = "." ]; then
                # Extract repository name from REPO_URL
                # Format: git@ssh.dev.azure.com:v3/Org/Project/RepoName
                REPO_NAME=$(echo "$REPO_URL" | sed -E 's|.*/([^/]+)$|\1|')
            else
                # Use the directory name (e.g., "./Services" -> "Services")
                REPO_NAME=$(basename "$REPO_PATH")
            fi
            
            # Create draft PR with issue number and title
            PR_TITLE="#${ISSUE_NUMBER} - ${ISSUE_TITLE}"
            
            # Attempt to create the PR
            if az repos pr create \
                --repository "$REPO_NAME" \
                --source-branch "$TARGET_BRANCH" \
                --target-branch "$MAIN_BRANCH" \
                --title "$PR_TITLE" \
                --draft true \
                --output none 2>/dev/null; then
                echo "   ✅ Draft PR created"
            else
                echo "   ⚠️  Could not create PR (may already exist or remote branch needed)"
            fi
        fi
        
    else
        # Branch exists - checkout and pull latest
        echo "   ✅ Branch exists, checking out..."
        
        # Fetch latest
        if ! git fetch origin 2>&1; then
            echo "   ❌ ERROR: Failed to fetch from remote origin"
            echo "Please verify git remote configuration and network connectivity"
            exit 1
        fi
        
        # Checkout the branch
        if [ "$BRANCH_EXISTS_LOCAL" -eq 0 ]; then
            # Remote only - create local tracking branch
            if ! git checkout -b "$TARGET_BRANCH" "origin/$TARGET_BRANCH" 2>&1; then
                echo "   ❌ ERROR: Failed to create tracking branch: $TARGET_BRANCH"
                exit 1
            fi
        else
            # Local exists - just checkout
            if ! git checkout "$TARGET_BRANCH" 2>&1; then
                echo "   ❌ ERROR: Failed to checkout branch: $TARGET_BRANCH"
                exit 1
            fi
        fi
        
        # Pull if remote exists
        if [ "$BRANCH_EXISTS_REMOTE" -gt 0 ]; then
            echo "   📥 Pulling latest changes..."
            if ! git pull origin "$TARGET_BRANCH" 2>&1; then
                echo "   ❌ ERROR: Failed to pull latest changes from: $TARGET_BRANCH"
                echo "Please resolve any conflicts or remote issues"
                exit 1
            fi
        fi
        
        echo "   ✅ On branch $TARGET_BRANCH with latest commits"
    fi
    
    # Return to workspace root
    cd - > /dev/null
done

echo ""
echo "✅ All repositories configured for issue #${ISSUE_NUMBER}"
echo "   Work branches: $BRANCH_NAME"
echo "   Scratchpad branches: scratchpad/${ISSUE_NUMBER}"
echo ""

# ============================================
# Spin up Copilot agent
# ============================================
echo "🤖 Starting GitHub Copilot agent: $AGENT_NAME"
echo ""

# Run copilot in yolo mode with the issue prompt
exec copilot yolo --agent "$AGENT_NAME" --prompt "Commence work on azure devops work item $ISSUE_NUMBER"
