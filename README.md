# Copilot Code Server Container

A containerized development environment for **agentic programming** with GitHub Copilot, designed for secure sandboxing and quick, replicatable setups.

## What is This?

This project provides a fully containerized [code-server](https://github.com/coder/code-server) environment (VS Code in the browser) pre-configured for GitHub Copilot agentic workflows. It's designed to give AI agents a safe, isolated workspace where they can code, build, test, and manage projects without affecting your host system.

**Key features include:**
- **Azure DevOps Integration**: Automated issue-based workflow with the `start-issue` command
- **Multi-repository Support**: Manage monorepos and submodules with deterministic branch strategies
- **Agent Safety**: Whitelisted repositories, safeguarded git operations, and locked Azure configurations
- **Full Development Stack**: .NET, Node.js, Python, Azure CLI, and more pre-installed

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
- **code-server**: Browser-based VS Code experience
- **GitHub Copilot**: Full Copilot support with custom MCP (Model Context Protocol) servers
- **Multi-language support**: Node.js, Python, .NET SDK 10.0 pre-installed
- **Development tools**: git, lazygit, zsh with oh-my-zsh, and more
- **Custom MCPs**: Extensible MCP configuration for enhanced agent capabilities

## Prerequisites

- Docker and Docker Compose installed on your system
- A GitHub Copilot subscription

## Quick Start

### 1. Configure Environment Variables

Create a `.env` file in the project root:

```bash
GIT_USERNAME=Your Name
GIT_EMAIL=your.email@example.com
```

These are **required** for git operations within the container.

Additionally, configure repository checkout settings in `docker-compose.yml`:

```yaml
environment:
  - REPO_URL=git@ssh.dev.azure.com:v3/YourOrg/YourProject/YourRepo
  - REPO_FOLDER=YourRepoName
```

- `REPO_URL`: SSH URL of the Azure DevOps repository to clone
- `REPO_FOLDER`: Directory name for the cloned repository (workspace root)

### 2. Run the Container

```bash
docker compose up -d --build
```

This command will:
- Build the Docker image
- Start the code-server container in detached mode
- Auto-generate SSH keys on first run
- Set up the agent environment

### 3. Get Your SSH Public Key

On first run, the container automatically generates an SSH key pair for git operations. To view your public key:

```bash
docker logs copilot-code-server
```

Look for the section that displays:
```
📋 Your public key (add this to Azure DevOps):
================================================
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ...
================================================
```

**Important**: Add this public key to your git hosting service (GitHub, Azure DevOps, GitLab, etc.) to enable git operations over SSH.

### 4. Access code-server

Open your browser and navigate to:
```
http://localhost:8080
```

You'll have a full VS Code environment running in your browser, ready for agentic development!

## Working with Azure DevOps Work Items

This container includes the `start-issue` command for streamlined issue-based development workflows with Azure DevOps integration.

### The `start-issue` Command

The `start-issue` command automates the entire workflow of starting work on an Azure DevOps work item:

1. **Fetches work item details** from Azure DevOps (title, description, acceptance criteria)
2. **Generates deterministic branch names** based on issue number and title (e.g., `1234-fix-login-bug`)
3. **Interactive repository selection** - prompts you to select which repos you want to actively work on
4. **Branch management** - creates work branches for selected repos, scratchpad branches for others
5. **Auto-spin up GitHub Copilot agent** in yolo mode, primed to work on the issue

### Usage

```bash
start-issue <issue-number> [--agent <agent-name>]
```

**Examples:**
```bash
# Start work on issue #1234 with default agent
start-issue 1234

# Start work on issue #1234 with custom agent name
start-issue 1234 --agent my-custom-agent
```

### What Happens When You Run It

1. **Authentication Check**: Verifies you're logged into Azure CLI (prompts if not)
2. **Fetch Work Item**: Retrieves issue details from Azure DevOps
3. **Branch Name Generation**: Creates a deterministic, readable branch name (max 24 chars)
4. **Repository Selection**: If on main branch, prompts which repos to work on (using `gum` for UI)
5. **Git Operations**: 
   - Selected repos → Creates/checks out work branch (e.g., `1234-fix-login-bug`)
   - Other repos → Creates/checks out scratchpad branch (e.g., `scratchpad/1234`)
6. **Draft Pull Request Creation**: For newly created work branches, automatically creates draft PRs with title format `#1234 - Issue Title`
7. **Agent Launch**: Spins up GitHub Copilot agent with prompt: "Commence work on azure devops work item 1234"

### Safety Features

- **Uncommitted changes check**: Won't switch branches if you have uncommitted work
- **Branch conflict detection**: Warns if you're on another issue's branch
- **Scratchpad isolation**: Non-selected repos get isolated scratchpad branches
- **Safe git push**: `git_push` command blocks scratchpad branches and checks for uncommitted changes

## Configuration Files

This project uses several mounted JSON configuration files that you can customize:

### `mcp-config.json` - MCP Server Configuration

Configures Model Context Protocol (MCP) servers that extend GitHub Copilot's capabilities. The default configuration includes:

```json
{
  "mcpServers": {
    "cli-mcp-mapper": {
      "type": "local",
      "command": "cli-mcp-mapper",
      "args": [],
      "tools": ["*"]
    }
  }
}
```

This file is mounted at `/home/agent/.copilot/mcp-config.json` inside the container.

**To add custom MCPs**:
1. Install the MCP package in the Dockerfile (add npm/pip install commands)
2. Add the MCP server configuration to `mcp-config.json`
3. Rebuild the container with `docker compose up -d --build`

### `vscode-settings.json` - VS Code Settings

Controls the code-server (VS Code) editor settings. Mounted at `/home/agent/.local/share/code-server/User/settings.json`.

Default settings include:
- GitHub Copilot enabled
- Inline suggestions enabled
- zsh as default terminal
- Abyss color theme
- Chat features configured for agent use

Customize this file to adjust your editor preferences.

### `commands.json` - CLI MCP Mapper Commands

Defines custom commands available to the agent through the [cli-mcp-mapper](https://github.com/SteffenBlake/cli-mcp-mapper) MCP server. This file is mounted at `/home/agent/.config/cli-mcp-mapper/commands.json`.

The default configuration includes commands for:
- **.NET operations**: build, restore, test, format
- **Git operations**: status, diff, branch, stage, unstage, restore, commit (with issue tracking), push (safeguarded)
- **Azure DevOps**: get work items, list PRs, get PR comments, list allowed repos
- **File system operations**: ls, mv, mkdir, rm, grep, sed, wc

**Git commit behavior**: The `git_commit` command automatically formats commits as `[#<issue>][Copilot] <message>` and attributes them to `<GIT_USERNAME>+copilot` for agent identification.

**Git push safety**: The `git_push` command includes safety checks:
- Blocks pushing scratchpad branches
- Checks for uncommitted changes before pushing
- Prevents accidental pushes of unfinished work

**Draft PR automation**: When `start-issue` creates a new work branch (not scratchpad), it automatically creates a draft pull request in Azure DevOps. The PR title follows the format `#<issue> - <title>`. Draft PRs are only created once when the branch is initially created, using branch creation as a semaphore to prevent duplicate PRs.

**To configure custom commands**, see the [cli-mcp-mapper documentation](https://github.com/SteffenBlake/cli-mcp-mapper) for detailed information on command structure and parameters.

### `repo-mappings.json` - Repository Configuration

Defines the workspace repository structure and main branch names for multi-repo projects. This file is used by the `start-issue` command to manage branches across multiple repositories (e.g., monorepo with submodules).

**Location**: Mounted at `/etc/repo-mappings.json` (read-only)

**Example structure**:
```json
{
  "repoMainBranches": {
    ".": "main",
    "./Services": "develop",
    "./Mobile": "develop",
    "./DataHub": "main"
  }
}
```

- **Keys**: Relative paths to repositories (`.` = workspace root, `./Services` = submodule)
- **Values**: The main/default branch name for each repository

The `start-issue` command uses this to:
- Know which repositories exist in your workspace
- Understand what the "main" branch is for each repo (for creating feature branches from)
- Manage branch creation across all configured repositories

**To add a repository**: Add a new entry with the relative path and its main branch name.

### `allowed-repositories.conf` - Azure DevOps Repository Whitelist

Defines which Azure DevOps repositories agents are allowed to access through Azure CLI commands. This is a security measure to restrict agent access.

**Location**: Mounted at `/etc/allowed-repositories.conf` (read-only)

**Format**: One repository name per line, comments start with `#`

**Example**:
```conf
# Azure DevOps Repositories that agents are allowed to access
# One repository name per line
# Lines starting with # are ignored
Aspire
Services
Mobile
DataHub
```

Agents can only interact with Azure DevOps repositories listed in this file. Commands like `az_devops_get_pull_requests` will validate repository parameters against this whitelist.

**To allow additional repositories**: Add the repository name on a new line.

**Security note**: Repository names are validated to contain only alphanumeric characters, dots, dashes, and underscores to prevent injection attacks.

## Azure DevOps Integration

The container includes Azure CLI with the Azure DevOps extension pre-installed, locked down for agent safety:

### Locked Configuration

The following are **locked at build time** in the Dockerfile and cannot be changed by agents:
- **Organization**: Set via `AZURE_DEVOPS_ORG` environment variable
- **Project**: Set via `AZURE_DEVOPS_PROJECT` environment variable

These ensure agents can only operate within your designated Azure DevOps organization and project.

### Agent Commands

Agents have access to these Azure DevOps commands (via `cli-mcp-mapper`):

- **`az_devops_get_work_item`**: Fetch work item details (description, acceptance criteria)
- **`az_devops_get_pull_requests`**: List open PRs for a repository
- **`az_devops_get_pr_comments`**: Get comment threads on a PR
- **`az_devops_list_repos`**: List allowed repositories

All commands automatically use the locked organization and project. Repository parameters are validated against the `allowed-repositories.conf` whitelist.

## Architecture

### Container Structure

- **Base Image**: Debian 13
- **User**: Locked-down `agent` user with minimal permissions
- **Workspace**: `/home/agent/workspace` (your working directory)
- **Persistent Storage**: The entire `/home/agent` directory is persisted in a Docker volume, preserving:
  - Configuration files
  - VS Code extensions
  - Workspace files
  - SSH keys
  - Git credentials

### Security Features

- **Non-root user**: All operations run as the `agent` user
- **Isolated credentials**: GPG and pass configured for secure credential storage
- **Container-specific SSH keys**: Generated per container, not shared with host
- **Home directory permissions**: Locked down to 700 (user-only access)

### Installed Tools

- **Languages**: Node.js, Python 3, .NET SDK 10.0, .NET Aspire CLI
- **Version Control**: git, lazygit
- **Azure Tools**: Azure CLI with Azure DevOps extension
- **UI Tools**: gum (interactive CLI prompts)
- **Security**: GPG, pass (password manager)
- **Shell**: zsh with oh-my-zsh (jonathan theme)
- **Editor**: code-server (VS Code in browser)
- **AI Tools**: GitHub Copilot CLI, cli-mcp-mapper
- **Custom Commands**: `start-issue` (Azure DevOps workflow automation)

## Common Tasks

### Start Work on an Issue

1. Access code-server in your browser at `http://localhost:8080`
2. Open a terminal in VS Code (`` Ctrl+` `` or `View > Terminal`)
3. Run the start-issue command:

```bash
start-issue 1234

# Or with custom agent name
start-issue 1234 --agent my-agent
```

The command will automatically prompt for Azure CLI authentication if needed.

### View Container Logs
```bash
docker logs copilot-code-server
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

### Open Terminal in Code-Server

Access `http://localhost:8080` in your browser, then:
- Press `` Ctrl+` `` (backtick), or
- Go to `View > Terminal` in the menu

All commands should be run from within the code-server terminal, not via `docker exec`.

### Reset Everything (Fresh Start)
```bash
docker compose down -v  # Warning: Deletes all container data!
docker compose up -d --build
```

## Persistent Data

All data in `/home/agent` is stored in a Docker named volume (`agent-home`), which persists between container restarts. This includes:

- Your workspace files
- Installed VS Code extensions
- Shell history and configuration
- SSH keys (generated on first run)
- Git credentials

To completely reset the environment, remove the volume with `docker compose down -v`.

## Port Configuration

- **8080**: code-server web interface (mapped to host port 8080)

To use a different port, modify the `ports` section in `docker-compose.yml`.

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

Extensions can be installed through the code-server UI and will persist in the `agent-home` volume.

### Configuring Azure DevOps

To change the Azure DevOps organization or project, edit the Dockerfile:

```dockerfile
# Set Azure DevOps configuration (locked at build time)
ENV AZURE_DEVOPS_ORG=YourOrgName
ENV AZURE_DEVOPS_PROJECT=YourProjectName
```

Then rebuild: `docker compose up -d --build`

**Important**: These values are intentionally locked at build time for security. Agents cannot modify them at runtime.

### Managing Repository Access

**To add allowed repositories**, edit `allowed-repositories.conf`:
```conf
YourNewRepo
AnotherRepo
```

**To configure workspace repositories**, edit `repo-mappings.json`:
```json
{
  "repoMainBranches": {
    ".": "main",
    "./YourSubmodule": "develop"
  }
}
```

Both files require a container rebuild to take effect: `docker compose up -d --build`

## Troubleshooting

### Container Fails to Start

Check logs for missing environment variables:
```bash
docker logs copilot-code-server
```

Ensure your `.env` file has `GIT_USERNAME` and `GIT_EMAIL` set.

### Repository Clone Takes Too Long

The container startup includes cloning your repository with all submodules. For large repositories, this can take several minutes.

**Symptoms**:
- Container logs show "Cloning into..." messages but no progress
- s6 timeout errors: "s6-rc: fatal: timed out" or "s6-sudoc: fatal: unable to get exit status from server: Operation timed out"

**Solution**:
There are two timeout settings that must both be high enough:

1. **Global s6 timeout** (most important): `S6_CMD_WAIT_FOR_SERVICES_MAXTIME` in Dockerfile
   - Default: 600000ms (10 minutes)
   - This is the maximum time for ALL services to start
   - If git clone takes longer than this, increase it in the Dockerfile ENV section

2. **Service-specific timeout**: `s6-overlay/s6-rc.d/agent-bootstrap/timeout-up`
   - Default: 600000ms (10 minutes)  
   - This is the timeout for the agent-bootstrap service specifically
   - Should match or exceed the global timeout

For extremely large repositories (>500MB, many submodules), increase both values proportionally.

**Note**: The `--progress` flag on git clone provides feedback during long operations, showing percentage and transfer speed.

### SSH Warnings During Clone

**"Warning: Permanently added 'ssh.dev.azure.com' (RSA) to the list of known hosts"**

This warning appears during the initial git clone when SSH connects to Azure DevOps for the first time. With `--recurse-submodules`, each submodule creates a separate SSH connection, so you might see this warning multiple times (once per repository).

**Why it happens**:
- SSH adds the host to `~/.ssh/known_hosts` on first connection
- Each submodule clone is a separate SSH connection
- The warning is informational and harmless

**Suppression**:
The SSH config includes `LogLevel ERROR` to suppress these informational warnings. If you still see them, it's normal for the first container startup and won't appear on subsequent runs.

### Can't Push to Git Repositories

1. Ensure you've added the container's SSH public key to your git host
2. Check the public key with: `docker logs copilot-code-server`
3. Verify git configuration from code-server terminal: `git config --list`

### start-issue Command Fails

**"Repository path does not exist"**:
- Verify `REPO_URL` and `REPO_FOLDER` are set correctly in `docker-compose.yml`
- Ensure the repository was cloned successfully on container start (check logs)
- Confirm all submodules are initialized from code-server terminal: `git submodule update --init --recursive`

**"Not logged in to Azure CLI"**:
- The `start-issue` command will automatically prompt for Azure authentication when needed
- Follow the interactive browser login flow

**"Repository not in allowed list"**:
- Check that the repository name exists in `allowed-repositories.conf`
- Repository names are case-sensitive

**"Config file not found"**:
- Verify `repo-mappings.json` is properly mounted in `docker-compose.yml`
- Ensure the file exists and contains valid JSON
- Check that root repository "." is defined in the mappings

### Azure DevOps Commands Don't Work

1. Verify Azure CLI is logged in from code-server terminal: `az account show`
2. Check organization/project settings in the Dockerfile match your Azure DevOps setup
3. Ensure you have permissions to access the work items/repositories
4. Confirm repository names in `allowed-repositories.conf` match exactly (case-sensitive)

### Port 8080 Already in Use

Change the host port in `docker-compose.yml`:
```yaml
ports:
  - "8081:8080"  # Use port 8081 instead
```

## License

See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

## Related Projects

- [code-server](https://github.com/coder/code-server) - VS Code in the browser
- [cli-mcp-mapper](https://github.com/SteffenBlake/cli-mcp-mapper) - CLI command MCP server
- [GitHub Copilot](https://github.com/features/copilot) - AI pair programmer