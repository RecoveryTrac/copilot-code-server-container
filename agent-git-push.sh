#!/bin/bash
set -e

# ============================================
# Agent Git Push - Safeguarded push for agents
# ============================================

# Determine target directory
TARGET_DIR="${1:-.}"

# Navigate to target directory
if [ ! -d "$TARGET_DIR" ]; then
    echo "❌ ERROR: Directory does not exist: $TARGET_DIR"
    exit 1
fi

cd "$TARGET_DIR"

# Verify this is a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ ERROR: Not a git repository: $(pwd)"
    exit 1
fi

# ============================================
# Check for uncommitted/unstaged changes
# ============================================

# Check for unstaged changes
UNSTAGED_COUNT=$(git diff --name-only | wc -l)

# Check for staged but uncommitted changes
STAGED_COUNT=$(git diff --cached --name-only | wc -l)

# Check for untracked files
UNTRACKED_COUNT=$(git ls-files --others --exclude-standard | wc -l)

TOTAL_CHANGES=$((UNSTAGED_COUNT + STAGED_COUNT + UNTRACKED_COUNT))

if [ $TOTAL_CHANGES -gt 0 ]; then
    echo "❌ ERROR: Cannot push - workspace has uncommitted changes"
    echo ""
    echo "   Repository: $(pwd)"
    echo "   Unstaged changes: $UNSTAGED_COUNT"
    echo "   Staged but uncommitted: $STAGED_COUNT"
    echo "   Untracked files: $UNTRACKED_COUNT"
    echo ""
    echo "   Please commit or stash all changes before pushing."
    echo ""
    
    if [ $UNSTAGED_COUNT -gt 0 ]; then
        echo "   Unstaged files:"
        git diff --name-only | sed 's/^/     - /'
        echo ""
    fi
    
    if [ $STAGED_COUNT -gt 0 ]; then
        echo "   Staged but uncommitted files:"
        git diff --cached --name-only | sed 's/^/     - /'
        echo ""
    fi
    
    if [ $UNTRACKED_COUNT -gt 0 ]; then
        echo "   Untracked files:"
        git ls-files --others --exclude-standard | sed 's/^/     - /'
        echo ""
    fi
    
    exit 1
fi

# ============================================
# Check for scratchpad branches
# ============================================

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [[ "$CURRENT_BRANCH" == scratchpad/* ]]; then
    echo "❌ ERROR: Cannot push scratchpad branch"
    echo ""
    echo "   Repository: $(pwd)"
    echo "   Current branch: $CURRENT_BRANCH"
    echo ""
    echo "   This repository has not been authorized for work on this issue."
    echo "   Scratchpad branches are for local tracking only and cannot be pushed."
    echo ""
    exit 1
fi

# ============================================
# Perform the push
# ============================================

echo "📤 Pushing branch: $CURRENT_BRANCH"
echo "   Repository: $(pwd)"

# Push current branch to origin
git push origin "$CURRENT_BRANCH"

echo "✅ Successfully pushed $CURRENT_BRANCH to origin"
