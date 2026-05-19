#!/bin/bash
set -euo pipefail

# ============================================
# Enable cgroup controllers for Docker-in-Docker
# ============================================
# Docker needs memory and io controllers to enforce resource limits on containers.
# Without these, containers have unlimited RAM and I/O, leading to swap thrashing.
# 
# Read current controllers, append memory and io if not already present, then write back.
# This ensures we don't override other controllers (like cpuset, cpu, pids).
CGROUP_CONTROL="/sys/fs/cgroup/cgroup.subtree_control"
CURRENT_CONTROLLERS=$(cat "$CGROUP_CONTROL" 2>/dev/null || echo "")

# Build the list of controllers to enable
CONTROLLERS_TO_ENABLE=""

# Always include existing controllers
for controller in $CURRENT_CONTROLLERS; do
    CONTROLLERS_TO_ENABLE="$CONTROLLERS_TO_ENABLE +$controller"
done

# Add memory controller if not present
if [[ ! "$CURRENT_CONTROLLERS" =~ memory ]]; then
    CONTROLLERS_TO_ENABLE="$CONTROLLERS_TO_ENABLE +memory"
    echo "✅ Enabling memory controller for Docker resource limits"
fi

# Add io controller if not present
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

# Disable swap for all containers created by the inner Docker daemon
echo 0 > /sys/fs/cgroup/memory.swap.max
echo "✅ Swap disabled for inner Docker containers"

# Ensure the agent user owns the entire .vscode-server bind-mount tree so that
# VS Code Remote-SSH can read and write freely (installing its server binary,
# writing logs, caching extensions, etc.).
chown -R agent:agent /home/agent/.vscode-server
echo "✅ .vscode-server ownership configured"
