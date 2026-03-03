#!/bin/bash
set -e

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

if [ $MISSING_CONFIG -eq 1 ]; then
    echo ""
    echo "💡 Please set all required Git environment variables in your .env file:"
    echo "   - GIT_USERNAME"
    echo "   - GIT_EMAIL"
    echo ""
    echo "Example .env file:"
    echo "GIT_USERNAME=Your Name"
    echo "GIT_EMAIL=your.email@example.com"
    exit 1
fi

echo "✅ Git configuration validated"

# Set both author and committer to the same values
export GIT_AUTHOR_NAME="$GIT_USERNAME"
export GIT_AUTHOR_EMAIL="$GIT_EMAIL"
export GIT_COMMITTER_NAME="$GIT_USERNAME"
export GIT_COMMITTER_EMAIL="$GIT_EMAIL"

# ============================================
# SSH key auto-generation (ed25519 only)
# ============================================
SSH_DIR="/home/agent/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"

# Remove any legacy id_rsa key pair left over from older container versions.
# We standardise on a single ed25519 key pair only.
if [ -f "$SSH_DIR/id_rsa" ] || [ -f "$SSH_DIR/id_rsa.pub" ]; then
    echo "🧹 Removing legacy id_rsa key pair (standardising on ed25519 only)..."
    rm -f "$SSH_DIR/id_rsa" "$SSH_DIR/id_rsa.pub"
    echo "✅ Legacy id_rsa removed"
fi

if [ ! -f "$SSH_KEY" ]; then
    echo "🔑 SSH keys not found. Generating new ed25519 SSH key pair..."
    mkdir -p "$SSH_DIR"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "${GIT_USERNAME} <${GIT_EMAIL}>"
    chmod 700 "$SSH_DIR"
    chmod 600 "$SSH_KEY"
    chmod 644 "$SSH_KEY.pub"
    echo "✅ SSH key pair generated at $SSH_KEY"
else
    echo "✅ SSH keys already exist at $SSH_KEY"
fi

# ============================================
# Setup authorized_keys for container SSH access
# ============================================
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
if [ ! -f "$AUTHORIZED_KEYS" ]; then
    cp "$SSH_KEY.pub" "$AUTHORIZED_KEYS"
    chmod 600 "$AUTHORIZED_KEYS"
    echo "✅ authorized_keys configured for Remote-SSH access"
fi

# ============================================
# Output VS Code Remote-SSH connection instructions
# ============================================
echo ""
echo "🚀 ============================================================"
echo "   VS Code Remote-SSH Connection Instructions"
echo "   ============================================================"
echo ""
echo "📋 Your public SSH key (add this to Azure DevOps / GitHub for git access):"
echo "------------------------------------------------"
cat "$SSH_KEY.pub"
echo "------------------------------------------------"
echo ""
echo "🔐 To connect via VS Code Remote-SSH:"
echo ""
echo "  1. Copy the private key below to your host machine:"
echo "     Save it as: ~/.ssh/copilot-dev-container"
echo "     Then run:   chmod 600 ~/.ssh/copilot-dev-container"
echo ""
echo "  ---- BEGIN PRIVATE KEY (copy everything between the lines) ----"
cat "$SSH_KEY"
echo "  ---- END PRIVATE KEY ----"
echo ""
echo "  2. Add the following to your host ~/.ssh/config:"
echo ""
echo "     Host copilot-dev"
echo "       HostName localhost"
echo "       Port 2222"
echo "       User agent"
echo "       IdentityFile ~/.ssh/copilot-dev-container"
echo "       StrictHostKeyChecking accept-new"
echo ""
echo "  3. In VS Code: F1 → 'Remote-SSH: Connect to Host' → copilot-dev"
echo ""
echo "🚀 ============================================================"
echo ""

# ============================================
# Configure git
# ============================================
git config --global user.name "$GIT_USERNAME"
git config --global user.email "$GIT_EMAIL"
echo "✅ Git configured: $GIT_USERNAME <$GIT_EMAIL>"

# Execute whatever command was passed (CMD or override)
exec "$@"
