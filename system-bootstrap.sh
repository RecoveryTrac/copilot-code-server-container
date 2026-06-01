#!/bin/bash
set -euo pipefail

# ============================================
# Enable cgroup controllers for Docker-in-Docker
# ============================================
# Docker needs memory and io controllers to enforce resource limits on containers.
# Without these, containers have unlimited RAM and I/O, leading to swap thrashing.

CGROUP_CONTROLLERS="/sys/fs/cgroup/cgroup.controllers"
CGROUP_CONTROL="/sys/fs/cgroup/cgroup.subtree_control"

# Check what controllers are available in the parent cgroup
AVAILABLE_CONTROLLERS=$(cat "$CGROUP_CONTROLLERS" 2>/dev/null || echo "")
CURRENT_CONTROLLERS=$(cat "$CGROUP_CONTROL" 2>/dev/null || echo "")

echo "Available controllers: $AVAILABLE_CONTROLLERS"
echo "Currently enabled: $CURRENT_CONTROLLERS"

# Check if memory and io controllers are available
MISSING_CONTROLLERS=""
if [[ ! "$AVAILABLE_CONTROLLERS" =~ memory ]]; then
    MISSING_CONTROLLERS="$MISSING_CONTROLLERS memory"
fi
if [[ ! "$AVAILABLE_CONTROLLERS" =~ io ]]; then
    MISSING_CONTROLLERS="$MISSING_CONTROLLERS io"
fi

if [ -n "$MISSING_CONTROLLERS" ]; then
    echo ""
    echo "❌ ERROR: Required cgroup controllers are not available:$MISSING_CONTROLLERS"
    echo ""
    echo "This container requires memory and io controllers to prevent swap thrashing."
    echo "The parent Docker container must be started with these options:"
    echo ""
    echo "  docker run --cgroupns=host ..."
    echo ""
    echo "Or if using docker-compose.yml:"
    echo ""
    echo "  services:"
    echo "    dev-container:"
    echo "      cgroup: host"
    echo ""
    echo "Then restart this container."
    exit 1
fi

# Build the list of controllers to enable
CONTROLLERS_TO_ENABLE=""

# Always include existing controllers
for controller in $CURRENT_CONTROLLERS; do
    CONTROLLERS_TO_ENABLE="$CONTROLLERS_TO_ENABLE +$controller"
done

# Add memory controller if not already enabled
if [[ ! "$CURRENT_CONTROLLERS" =~ memory ]]; then
    CONTROLLERS_TO_ENABLE="$CONTROLLERS_TO_ENABLE +memory"
    echo "✅ Enabling memory controller for Docker resource limits"
fi

# Add io controller if not already enabled
if [[ ! "$CURRENT_CONTROLLERS" =~ io ]]; then
    CONTROLLERS_TO_ENABLE="$CONTROLLERS_TO_ENABLE +io"
    echo "✅ Enabling io controller for Docker resource limits"
fi

# Write the controllers (strip leading space)
CONTROLLERS_TO_ENABLE=$(echo "$CONTROLLERS_TO_ENABLE" | sed 's/^ //')
if [ -n "$CONTROLLERS_TO_ENABLE" ]; then
    echo "$CONTROLLERS_TO_ENABLE" > "$CGROUP_CONTROL"
    echo "✅ Cgroup controllers enabled: $(cat $CGROUP_CONTROL)"
fi

# Ensure the agent user owns the entire .vscode-server bind-mount tree so that
# VS Code Remote-SSH can read and write freely (installing its server binary,
# writing logs, caching extensions, etc.).
chown -R agent:agent /home/agent/.vscode-server
echo "✅ .vscode-server ownership configured"
