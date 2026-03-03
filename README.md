# Copilot Dev Container (VS Code Remote-SSH)

A containerized development environment for **agentic programming** with GitHub Copilot, accessed via **VS Code Remote-SSH** for full official Copilot support. Designed for secure sandboxing, Docker-in-Docker, and quick, replicatable setups.

## What is This?

This project provides a fully containerized development environment pre-configured for GitHub Copilot agentic workflows. It uses **VS Code Remote-SSH** so developers connect with their local VS Code installation—meaning full, official GitHub Copilot support (no browser workarounds). The container runs a locked-down `agent` user with Docker-in-Docker, a pre-bootstrapped shell, and a git-tracked extensions directory so the whole team shares the same VS Code setup.

```
┌─────────────────────────────────────────────┐
│  Your Host Machine                          │
│                                             │
│  ┌─────────────┐    SSH (port 2222)         │
│  │  VS Code    │◄──────────────────────┐    │
│  │  + Copilot  │                       │    │
│  └─────────────┘   ┌───────────────────▼──┐ │
│                    │  Docker Container    │ │
│                    │  ┌───────────────┐   │ │
│                    │  │  sshd :2222   │   │ │
│                    │  │  dockerd      │   │ │
│                    │  │  agent user   │   │ │
│                    │  │  zsh / git    │   │ │
│                    │  │  Node/Py/.NET │   │ │
│                    │  └───────────────┘   │ │
│                    └──────────────────────┘ │
└─────────────────────────────────────────────┘
```

## Why Use This?

### 🔒 Sandboxing & Security
- **Isolated environment**: AI agents run in a locked-down container with a dedicated user account
- **No host contamination**: All agent operations are contained within Docker volumes
- **Safe experimentation**: Let agents try things without risking your main development machine
- **Credential isolation**: SSH keys and credentials are container-specific

### 🚀 Quick & Replicatable
- **Instant setup**: One command gets you a fully configured development environment
- **Consistent environment**: Same setup across all machines and team members
- **Version controlled configuration**: All settings in JSON files you can track and share
- **Easy reset**: Delete the container and volume to start fresh anytime

### 🛠️ Pre-configured Tooling
- **VS Code Remote-SSH**: Full native VS Code experience with official GitHub Copilot
- **GitHub Copilot**: Full Copilot + Copilot Chat support with custom MCP servers
- **Docker-in-Docker**: Run Docker commands inside the container
- **Multi-language support**: Node.js, Python, .NET SDK 10.0 pre-installed
- **Development tools**: git, lazygit, zsh with oh-my-zsh, and more
- **Custom MCPs**: Extensible MCP configuration for enhanced agent capabilities

## Prerequisites

- Docker and Docker Compose installed on your system
- VS Code with the [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension installed
- A GitHub Copilot subscription

## Quick Start

### 1. Configure Environment Variables

Create a `.env` file in the project root:

```bash
GIT_USERNAME=Your Name
GIT_EMAIL=your.email@example.com
```

These are **required** for git operations within the container.

### 2. Start the Container

```bash
docker compose up -d --build
```

This will build the image and start the container. On first run, it automatically:
- Generates an ed25519 SSH key pair for the agent
- Sets up `authorized_keys` for Remote-SSH access
- Bootstraps the git and shell environment

### 3. Extract the SSH Private Key

Run the following to see the connection instructions printed by the container on startup:

```bash
docker logs copilot-dev-container
```

Look for the section that displays:

```
🚀 ============================================================
   VS Code Remote-SSH Connection Instructions
   ============================================================

🔐 To connect via VS Code Remote-SSH:

  1. Copy the private key below to your host machine:
     Save it as: ~/.ssh/copilot-dev-container
     Then run:   chmod 600 ~/.ssh/copilot-dev-container

  ---- BEGIN PRIVATE KEY (copy everything between the lines) ----
-----BEGIN OPENSSH PRIVATE KEY-----
...
-----END OPENSSH PRIVATE KEY-----
  ---- END PRIVATE KEY ----
```

Save the private key to `~/.ssh/copilot-dev-container` on your host machine and set permissions:

```bash
chmod 600 ~/.ssh/copilot-dev-container
```

### 4. Configure SSH on Your Host

Add the following to your `~/.ssh/config`:

```
Host copilot-dev
  HostName localhost
  Port 2222
  User agent
  IdentityFile ~/.ssh/copilot-dev-container
  StrictHostKeyChecking accept-new
```

### 5. Configure VS Code Remote-SSH Settings

Before connecting for the first time, open VS Code Settings (**File → Preferences → Settings** or **Cmd/Ctrl+,**) and set:

```json
"remote.SSH.localServerDownload": "always"
```

This tells VS Code to download its server component locally and copy it to the container via SCP, rather than trying to download it from inside the container. This is the recommended approach and avoids network issues inside the container.

> **Why?** VS Code Remote-SSH needs to install a ~100 MB "VS Code Server" binary on the remote machine on first connection. With `localServerDownload: "always"` VS Code downloads the binary on your host machine and copies it to the container via SSH. Without this setting VS Code tries to download the server from inside the container, which can fail if the container's outbound internet access is limited.

### 6. Connect via VS Code Remote-SSH

1. Open VS Code
2. Press **F1** (or **Ctrl+Shift+P**)
3. Type **Remote-SSH: Connect to Host**
4. Select **copilot-dev**

On first connection VS Code will show **"Setting up SSH Host copilot-dev: Copying VS Code Server to host with scp"**. This copies ~100 MB over SSH and may take 30–60 seconds depending on your network speed. Subsequent connections are instant because the server is cached in the container's volume.

VS Code will open a new window connected to the dev environment. The default workspace is at `/home/agent/workspace`.

### 7. Add Git SSH Key (Optional)

The container also prints your **public** SSH key for git hosting services:

```
📋 Your public SSH key (add this to Azure DevOps / GitHub for git access):
------------------------------------------------
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... your.email@example.com
------------------------------------------------
```

Add this key to your git hosting service (GitHub, Azure DevOps, GitLab, etc.) to enable authenticated git operations over SSH from within the container.

## Configuration Files

### `vscode-server/data/Machine/settings.json` - VS Code Remote Settings

Controls VS Code editor settings applied on the remote container. Mounted (as part of the full `./vscode-server` bind-mount) at `/home/agent/.vscode-server/data/Machine/settings.json`.

Default settings include:
- GitHub Copilot enabled
- Inline suggestions enabled
- zsh as default terminal
- Abyss color theme
- Copilot Chat agent mode enabled

### `vscode-server/data/User/mcp.json` - MCP Server Configuration

Configures Model Context Protocol (MCP) servers that extend GitHub Copilot's capabilities in VS Code. Mounted at `/home/agent/.vscode-server/data/User/mcp.json`.

### `commands.json` - CLI MCP Mapper Commands

Defines custom commands available to the agent through the [cli-mcp-mapper](https://github.com/SteffenBlake/cli-mcp-mapper) MCP server. Mounted at `/home/agent/.config/cli-mcp-mapper/commands.json`.

## Architecture

### Container Structure

- **Base Image**: Debian 13
- **Init System**: s6-overlay (manages sshd, dockerd, bootstrap services)
- **SSH Server**: OpenSSH on port 2222 (key-based auth only, agent user only)
- **User**: Locked-down `agent` user with docker group access
- **Workspace**: `/home/agent/workspace`
- **Persistent Storage**: `/home/agent` persisted in a Docker named volume

### s6-overlay Services

| Service | Type | Description |
|---------|------|-------------|
| `agent-bootstrap` | oneshot | Validates env, generates SSH keys, configures git |
| `sshd` | longrun | OpenSSH server on port 2222 |
| `dockerd` | longrun | Docker daemon (Docker-in-Docker) |

### Security Features

- **Non-root user**: All development operations run as the `agent` user
- **Key-based SSH only**: Password authentication disabled
- **Agent-only SSH access**: `AllowUsers agent` in sshd_config
- **No root SSH login**: `PermitRootLogin no`
- **Isolated credentials**: GPG and pass configured for secure credential storage
- **Home directory permissions**: Locked down to 700

### Installed Tools

- **Languages**: Node.js, Python 3, .NET SDK 10.0
- **Version Control**: git, lazygit
- **Security**: GPG, pass (password manager), OpenSSH
- **Shell**: zsh with oh-my-zsh (jonathan theme)
- **AI Tools**: cli-mcp-mapper
- **Docker**: Docker Engine + Docker Compose plugin

## Common Tasks

### View Container Logs

```bash
docker logs copilot-dev-container
```

### Restart the Container

```bash
docker compose restart
```

### Stop the Container

```bash
docker compose down
```

### Rebuild After Configuration Changes

```bash
docker compose up -d --build
```

### Access Container Shell Directly

```bash
docker exec -it copilot-dev-container zsh
```

### Reset Everything (Fresh Start)

```bash
docker compose down -v  # Warning: Deletes all container data!
docker compose up -d --build
```

## Persistent Data

Agent home (`/home/agent`) is stored in a Docker named volume (`agent-home`), which persists between container restarts. This includes workspace files, shell history, SSH keys, and git credentials.

The entire `./vscode-server/` directory is bind-mounted at `/home/agent/.vscode-server/`. This means VS Code server state, settings, MCP configuration, and extensions are all stored on the host and tracked in this git repo.

To completely reset the environment, remove the volume with `docker compose down -v` (your committed `vscode-server/` content is unaffected, being in the repo, not the volume).

## Port Configuration

| Port | Purpose |
|------|---------|
| **2222** | SSH (VS Code Remote-SSH connection) |
| **17275** | GitHub Copilot authentication callback |
| **65432** | cli-mcp-mapper MCP server |

To use a different SSH port, modify the `ports` section in `docker-compose.yml` and update your `~/.ssh/config` accordingly.

## Customization

### Installing Additional Tools

Edit the `Dockerfile` to add more tools:

```dockerfile
RUN apt-get update && apt-get install -y \
    your-package-here \
    && rm -rf /var/lib/apt/lists/*
```

### Changing the Shell Theme

Modify the `ZSH_THEME` environment variable in `docker-compose.yml`:

```yaml
environment:
  - ZSH_THEME=robbyrussell  # or any oh-my-zsh theme
```

### Adding VS Code Extensions

Extensions are managed via the **git-tracked `vscode-server/extensions/` directory** in this repo, which is part of the `./vscode-server` bind-mount at `~/.vscode-server/`.

**Workflow:**

1. Connect to the container via VS Code Remote-SSH
2. Install extensions normally through the VS Code Extensions panel (Ctrl+Shift+X)
3. Back on your host machine, the installed extensions appear in `./vscode-server/extensions/`
4. Commit the directory to share extensions with the team:

```bash
git add vscode-server/extensions/
git commit -m "Add VS Code extensions: github.copilot, ..."
git push
```

When a team member clones the repo and starts the container, VS Code finds the extensions pre-installed in the bind-mounted directory — no manual install needed.

## Troubleshooting

### Container Fails to Start

Check logs for missing environment variables:

```bash
docker logs copilot-dev-container
```

Ensure your `.env` file has `GIT_USERNAME` and `GIT_EMAIL` set.

### "Copying VS Code Server" Spinner Hangs Forever

This means `remote.SSH.localServerDownload` is not set to `"always"`, or the VS Code Server download is not being found. Follow these steps:

1. Open VS Code Settings (**Cmd/Ctrl+,**) and search for `remote.SSH.localServerDownload`
2. Set it to **"always"** (not "off" or "auto")
3. Reconnect — VS Code will download the server locally and copy it via SCP

If it still hangs after setting `localServerDownload: "always"`, the SCP copy itself is likely timing out. Try connecting from a faster network or check for MTU issues between your machine and the container host.

### "VS Code Server Could Not Be Downloaded" Error

This means VS Code is trying to download the server from inside the container, and the container can't reach the VS Code CDN. Fix:

Set `remote.SSH.localServerDownload: "always"` in VS Code Settings — this makes VS Code download the server on your local machine and copy it over SSH instead.

### Can't Connect via Remote-SSH

1. Ensure the container is running: `docker ps`
2. Check that the SSH key has correct permissions: `chmod 600 ~/.ssh/copilot-dev-container`
3. Verify SSH config entry in `~/.ssh/config`
4. Test SSH connectivity: `ssh copilot-dev`
5. Check container SSH logs: `docker logs copilot-dev-container`

### Can't Push to Git Repositories

1. Ensure you've added the container's public SSH key to your git host
2. Check the public key with: `docker logs copilot-dev-container`
3. Test git SSH: `ssh -T git@github.com` (from inside the container)

### Port 2222 Already in Use

Change the host port in `docker-compose.yml`:

```yaml
ports:
  - "2223:2222"  # Use port 2223 instead
```

Update your `~/.ssh/config` to match:

```
Host copilot-dev
  Port 2223
```

## License

See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

## Related Projects

- [VS Code Remote-SSH](https://code.visualstudio.com/docs/remote/ssh) - Connect to remote machines with VS Code
- [cli-mcp-mapper](https://github.com/SteffenBlake/cli-mcp-mapper) - CLI command MCP server
- [GitHub Copilot](https://github.com/features/copilot) - AI pair programmer