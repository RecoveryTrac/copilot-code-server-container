FROM debian:13

ARG S6_OVERLAY_VERSION=3.2.1.0

# ============================================
# IMPORTANT: Windows Line Ending Handling
# ============================================
# When building on Windows hosts, copied shell scripts may contain CRLF (\\r\\n) line endings.
# Linux requires LF (\\n) line endings. Scripts with CRLF fail with "No such file or directory"
# errors because the shebang becomes "#!/bin/bash\\r" (looking for /bin/bash\\r which doesn't exist).
#
# Solution: After COPY operations for shell scripts, we run sed -i 's/\\r$//' to strip carriage
# returns. This is done in the same RUN layer as chmod for efficiency (single layer, fast).
# ============================================

# ============================================
# PHASE 1: Install all package repository keys
# ============================================
# Install base tools and Docker GPG key
RUN apt-get update && apt-get install -y ca-certificates curl gnupg wget \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && rm -rf /var/lib/apt/lists/*

# Docker repository
RUN . /etc/os-release \
    && tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# Microsoft and Charm GPG keys and repositories
RUN wget https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb -O packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list

# ============================================
# PHASE 2: Single apt update with all repositories
# ============================================
RUN apt-get update

# ============================================
# PHASE 3: Apt Install - Chunk 1 (Large, expensive, low-volatility packages)
# ============================================
RUN apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    dotnet-sdk-10.0 \
    git \
    openssh-client \
    zsh \
    lazygit \
    iptables \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# PHASE 4: Apt Install - Chunk 2 (Medium packages)
# ============================================
RUN apt-get update && apt-get install -y \
    nodejs \
    npm \
    python3 \
    wget \
    curl \
    ca-certificates \
    xz-utils \
    tar \
    bash \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# PHASE 5: Apt Install - Chunk 3 (Small, frequently updated packages)
# ============================================
RUN apt-get update && apt-get install -y \
    gum \
    jq \
    pass \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# PHASE 6-7: Install s6-overlay and clean up package keys
# ============================================
RUN ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in \
    amd64)  S6_ARCH=x86_64  ;; \
    arm64)  S6_ARCH=aarch64 ;; \
    *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && curl -fsSL -o /tmp/s6-overlay-noarch.tar.xz \
    "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
    && curl -fsSL -o /tmp/s6-overlay-arch.tar.xz \
    "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
    && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz \
    && rm -f /tmp/s6-overlay-noarch.tar.xz /tmp/s6-overlay-arch.tar.xz \
    && rm -f /etc/apt/keyrings/docker.asc \
    /etc/apt/keyrings/charm.gpg \
    /etc/apt/sources.list.d/docker.sources \
    /etc/apt/sources.list.d/charm.list

# ============================================
# PHASE 8: Create agent user (required before language tools)
# ============================================
RUN useradd -m -s /bin/zsh agent && \
    mkdir -p /home/agent/workspace && \
    chown -R agent:agent /home/agent && \
    chmod 700 /home/agent && \
    groupadd -f docker && \
    usermod -aG docker agent

# ============================================
# PHASE 9: Install expensive third-party tools (low volatility)
# ============================================
# Azure CLI (expensive, low volatility)
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# ============================================
# Install OpenSSH server
# ============================================
RUN apt-get update && apt-get install -y openssh-server && rm -rf /var/lib/apt/lists/*

# Configure sshd: port 2222, key-based auth only, agent user only
RUN mkdir -p /run/sshd && \
    { \
    echo ''; \
    echo '# Remote-SSH configuration'; \
    echo 'Port 2222'; \
    echo 'PasswordAuthentication no'; \
    echo 'PubkeyAuthentication yes'; \
    echo 'PermitRootLogin no'; \
    echo 'AllowUsers agent'; \
    echo '# Only listen on IPv4 – avoids ::1 healthcheck log spam and'; \
    echo '# simplifies VS Code Remote-SSH port-forwarding.'; \
    echo 'AddressFamily inet'; \
    echo '# Suppress any banner / last-login output.  VS Code Remote-SSH'; \
    echo '# uses the SCP protocol to copy its server binary; any bytes'; \
    echo '# output by sshd before the scp(1) ready-byte corrupt the'; \
    echo '# handshake and cause the "Copying VS Code Server" spinner to'; \
    echo '# hang forever.'; \
    echo 'PrintMotd no'; \
    echo 'PrintLastLog no'; \
    echo '# Keep SSH connections alive during long file transfers.'; \
    echo 'TCPKeepAlive yes'; \
    echo 'ClientAliveInterval 60'; \
    echo 'ClientAliveCountMax 10'; \
    } >> /etc/ssh/sshd_config && \
    ssh-keygen -A

# ============================================
# PHASE 10: Install language-specific tools (medium volatility)
# ============================================
# .NET tools
RUN dotnet tool install --global roslyn-language-server --prerelease

# Node.js global packages
RUN npm install -g typescript-language-server typescript cli-mcp-mapper

# ============================================
# PHASE 11: Install Azure DevOps extension (depends on Azure CLI)
# ============================================
RUN az extension add --name azure-devops

RUN mkdir -p /usr/local/share/copilot-code-server-container
COPY entrypoint.sh /usr/local/share/copilot-code-server-container/agent-bootstrap.sh
RUN chmod 0755 /usr/local/share/copilot-code-server-container/agent-bootstrap.sh
COPY system-bootstrap.sh /usr/local/share/copilot-code-server-container/system-bootstrap.sh
RUN chmod 0755 /usr/local/share/copilot-code-server-container/system-bootstrap.sh

# ============================================
# PHASE 12: Agent user environment setup (low volatility)
# ============================================
COPY ./container-log-prefixer.sh /usr/local/share/copilot-code-server-container/container-log-prefixer.sh
RUN chmod +x /usr/local/share/copilot-code-server-container/container-log-prefixer.sh

COPY s6-overlay/ /etc/s6-overlay/

RUN chmod +x \
    /etc/s6-overlay/s6-rc.d/system-bootstrap/up \
    /etc/s6-overlay/s6-rc.d/sshd/run \
    /etc/s6-overlay/s6-rc.d/sshd/log/run \
    /etc/s6-overlay/s6-rc.d/dockerd/run \
    /etc/s6-overlay/s6-rc.d/dockerd/log/run \
    /etc/s6-overlay/s6-rc.d/agent-bootstrap/up

# Remove any legacy s6 service directories that external install scripts may
# have created (e.g. code-server registers /etc/services.d/code-server/).
# All services for this container are compiled into s6-rc-compiled; legacy
# service discovery must not start unexpected processes.
# Placed here, after all external installs, to act as a final clean-up guard.
RUN rm -rf /etc/services.d/ /etc/cont-init.d/

RUN /command/s6-rc-compile /etc/s6-overlay/s6-rc-compiled /etc/s6-overlay/s6-rc.d

# S6_CMD_WAIT_FOR_SERVICES_MAXTIME: Set to 10 minutes to allow git clone with large submodules
ENV S6_CMD_WAIT_FOR_SERVICES=1
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=600000
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

# Switch to agent user for agent-owned config initialization
USER agent

ENV SHELL=/usr/bin/zsh \
    HOME=/home/agent \
    USER=agent \
    LOGNAME=agent \
    PATH="${PATH}:/home/agent/.dotnet/tools"

# Aspire CLI (low-medium expense, medium volatility, must be run by the agent)
RUN curl -sSL https://aspire.dev/install.sh | bash

# Install oh-my-zsh for agent user
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Initialize GPG and pass for credential storage
RUN gpg --batch --gen-key <<EOF && \
    pass init "agent@localhost"
%no-protection
Key-Type: RSA
Key-Length: 2048
Name-Real: Code Server Agent
Name-Email: agent@localhost
Expire-Date: 0
EOF

# Create base VS Code server directory; the full tree is provided at runtime
# by the ./vscode-server bind-mount in docker-compose.yml.
RUN mkdir -p /home/agent/.vscode-server

# ============================================
# PHASE 13: Copy high-volatility agent scripts and configs
# ============================================
USER root

# Copy all agent scripts and configs
# Note: When building on Windows, scripts may have CRLF line endings
COPY entrypoint.sh /usr/local/share/copilot-code-server-container/agent-bootstrap.sh
COPY start-issue.sh /usr/local/bin/start-issue
COPY agent-git-push.sh /usr/local/bin/agent-git-push
COPY agent-git-commit.sh /usr/local/bin/agent-git-commit
COPY agent-az-devops.sh /usr/local/bin/agent-az-devops
COPY agent-az-devops-list-repositories.sh /usr/local/bin/agent-az-devops-list-repositories
COPY repo-mappings.json allowed-repositories.conf /etc/

# Fix Windows line endings (CRLF → LF) and set permissions in one layer
# Without this, scripts fail with "No such file or directory" errors on Linux
RUN sed -i 's/\r$//' /usr/local/share/copilot-code-server-container/agent-bootstrap.sh \
    /usr/local/bin/start-issue \
    /usr/local/bin/agent-git-push \
    /usr/local/bin/agent-git-commit \
    /usr/local/bin/agent-az-devops \
    /usr/local/bin/agent-az-devops-list-repositories && \
    chmod 0755 /usr/local/share/copilot-code-server-container/agent-bootstrap.sh && \
    chmod +x /usr/local/bin/start-issue \
    /usr/local/bin/agent-git-push \
    /usr/local/bin/agent-git-commit \
    /usr/local/bin/agent-az-devops \
    /usr/local/bin/agent-az-devops-list-repositories

# ============================================
# PHASE 14: Set Azure DevOps environment (medium-high volatility)
# ============================================
ENV AZURE_DEVOPS_ORG=TDRRecoveryTrac \
    AZURE_DEVOPS_PROJECT=RecoveryTrac

# ============================================
# PHASE 15: Configure s6 services (high volatility)
# ============================================
COPY ./container-log-prefixer.sh /usr/local/share/copilot-code-server-container/container-log-prefixer.sh
COPY s6-overlay/ /etc/s6-overlay/

# Fix Windows line endings (CRLF → LF) for all s6 files and scripts
# The find command ensures ALL s6 script files have Unix line endings
RUN find /etc/s6-overlay -type f -exec sed -i 's/\r$//' {} \;

# S6_CMD_WAIT_FOR_SERVICES_MAXTIME: Set to 10 minutes to allow git clone with large submodules
ENV DOCKER_HOST=unix:///var/run/docker.sock

# ============================================
# PHASE 16: Final runtime configuration
# ============================================
WORKDIR /home/agent/workspace

EXPOSE 2222

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD bash -c 'echo > /dev/tcp/127.0.0.1/2222' || exit 1

# s6 init must run as root so dockerd and sshd can start properly
USER root

ENTRYPOINT ["/init"]
