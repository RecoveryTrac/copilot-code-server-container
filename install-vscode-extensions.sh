#!/bin/bash
# This script is run as the 'agent' user (s6-setuidgid agent in the oneshot up file).
# All files and directories created here are therefore already owned by agent; no
# explicit chown calls are needed.
set -e

FLAG_FILE="/home/agent/.vscode-extensions-installed"

if [ -f "$FLAG_FILE" ]; then
    echo "✅ VS Code extensions already installed, skipping"
    exit 0
fi

echo "📦 Downloading VS Code CLI..."

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  VS_ARCH="x64"   ;;
    aarch64) VS_ARCH="arm64" ;;
    *) echo "⚠️  Unsupported architecture: $ARCH, skipping extension install"; exit 0 ;;
esac

if ! curl -fsSL "https://code.visualstudio.com/sha/download?build=stable&os=cli-linux-${VS_ARCH}" \
        -o /tmp/vscode-cli.tar.gz; then
    echo "⚠️  Could not download VS Code CLI, skipping extension pre-install (extensions will install on first VS Code connection)"
    exit 0
fi

if ! tar -xzf /tmp/vscode-cli.tar.gz -C /tmp; then
    echo "⚠️  Could not extract VS Code CLI, skipping extension pre-install"
    rm -f /tmp/vscode-cli.tar.gz
    exit 0
fi
rm -f /tmp/vscode-cli.tar.gz

echo "🔌 Pre-installing VS Code extensions..."

EXTENSIONS_DIR="/home/agent/.vscode-server/extensions"
mkdir -p "$EXTENSIONS_DIR"

for EXT in \
    "github.copilot" \
    "github.copilot-chat" \
    "ms-dotnettools.csharp" \
    "ms-azuretools.vscode-docker"; do

    echo "  Installing $EXT..."
    /tmp/code --extensions-dir "$EXTENSIONS_DIR" --install-extension "$EXT" --force || \
        echo "  ⚠️  Could not pre-install $EXT (will install on first VS Code connection)"
done

rm -f /tmp/code

touch "$FLAG_FILE"
echo "✅ VS Code extension pre-installation complete"
