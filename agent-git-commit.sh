#!/bin/bash
set -e

# ============================================
# Agent Git Commit - Formatted commit with issue number
# ============================================

# Parse parameters
ISSUE_NUMBER=""
MESSAGE=""
DIRECTORY="."

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --issue-number)
            ISSUE_NUMBER="$2"
            shift 2
            ;;
        --message)
            MESSAGE="$2"
            shift 2
            ;;
        --directory)
            DIRECTORY="$2"
            shift 2
            ;;
        *)
            echo "❌ ERROR: Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$ISSUE_NUMBER" ]; then
    echo "❌ ERROR: Issue number is required"
    echo "Usage: agent-git-commit --issue-number <number> --message <message> [--directory <path>]"
    exit 1
fi

if [ -z "$MESSAGE" ]; then
    echo "❌ ERROR: Commit message is required"
    echo "Usage: agent-git-commit --issue-number <number> --message <message> [--directory <path>]"
    exit 1
fi

# Navigate to target directory
if [ ! -d "$DIRECTORY" ]; then
    echo "❌ ERROR: Directory does not exist: $DIRECTORY"
    exit 1
fi

cd "$DIRECTORY"

# Verify this is a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ ERROR: Not a git repository: $(pwd)"
    exit 1
fi

# Format commit message with issue number and Copilot tag
FORMATTED_MESSAGE="[#${ISSUE_NUMBER}][Copilot] ${MESSAGE}"

echo "📝 Committing changes..."
echo "   Repository: $(pwd)"
echo "   Message: $FORMATTED_MESSAGE"

# Perform the commit with formatted message
git -c "user.name=${GIT_USERNAME}+copilot" \
    -c "user.email=${GIT_EMAIL}+copilot" \
    commit -am "$FORMATTED_MESSAGE"

echo "✅ Successfully committed changes"
