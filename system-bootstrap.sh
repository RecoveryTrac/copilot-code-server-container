#!/bin/bash
set -euo pipefail

# Ensure the agent user owns the entire .vscode-server bind-mount tree so that
# VS Code Remote-SSH can read and write freely (installing its server binary,
# writing logs, caching extensions, etc.).
chown -R agent:agent /home/agent/.vscode-server
