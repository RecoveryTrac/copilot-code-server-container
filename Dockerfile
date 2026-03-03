FROM debian:13

ARG S6_OVERLAY_VERSION=3.2.1.0

# Install base dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    openssh-client \
    zsh \
    lazygit \
    pass \
    iptables \
    iproute2 \
    xz-utils \
    tar \
    bash \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# Install Docker Engine (official Debian instructions style)
# ============================================
RUN apt-get update \
    && apt-get install -y ca-certificates curl \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && . /etc/os-release \
    && tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

RUN apt-get update \
    && apt-get install -y \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# Install s6-overlay (minimal init + service supervisor)
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
    && rm -f /tmp/s6-overlay-noarch.tar.xz /tmp/s6-overlay-arch.tar.xz

# ============================================
# Create locked-down agent user with "inner" docker daemon access
# ============================================
RUN useradd -m -s /bin/zsh agent && \
    mkdir -p /home/agent/workspace && \
    chown -R agent:agent /home/agent && \
    chmod 700 /home/agent && \
    groupadd -f docker && \
    usermod -aG docker agent

# ============================================
# Install Node.js + npm
# ============================================
RUN apt-get update && \
    apt-get install -y nodejs npm && \
    rm -rf /var/lib/apt/lists/*

# ============================================
# Install Python 3
# ============================================
RUN apt-get update && \
    apt-get install -y python3 && \
    rm -rf /var/lib/apt/lists/*

# ============================================
# Install .NET SDK 10.0
# ============================================
RUN wget https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb -O packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && \
    rm packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y dotnet-sdk-10.0 && \
    rm -rf /var/lib/apt/lists/*

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
# Install cli-mcp-mapper
# ============================================
RUN npm i -g cli-mcp-mapper

# ============================================
# Store agent bootstrap script in immutable image path (not volume-backed)
# ============================================
RUN mkdir -p /usr/local/share/copilot-code-server-container
COPY entrypoint.sh /usr/local/share/copilot-code-server-container/agent-bootstrap.sh
RUN chmod 0755 /usr/local/share/copilot-code-server-container/agent-bootstrap.sh
COPY system-bootstrap.sh /usr/local/share/copilot-code-server-container/system-bootstrap.sh
RUN chmod 0755 /usr/local/share/copilot-code-server-container/system-bootstrap.sh

# ============================================
# Configure s6 services
# ============================================
COPY ./container-log-prefixer.sh /usr/local/share/copilot-code-server-container/container-log-prefixer.sh
RUN chmod +x /usr/local/share/copilot-code-server-container/container-log-prefixer.sh

COPY s6-overlay/ /etc/s6-overlay/

RUN chmod +x \
  /etc/s6-overlay/s6-rc.d/system-bootstrap/up \
  /etc/s6-overlay/s6-rc.d/sshd/run \
  /etc/s6-overlay/s6-rc.d/sshd/log/run \
  /etc/s6-overlay/s6-rc.d/dockerd/run \
  /etc/s6-overlay/s6-rc.d/dockerd/log/run 

# Remove any legacy s6 service directories that external install scripts may
# have created (e.g. code-server registers /etc/services.d/code-server/).
# All services for this container are compiled into s6-rc-compiled; legacy
# service discovery must not start unexpected processes.
# Placed here, after all external installs, to act as a final clean-up guard.
RUN rm -rf /etc/services.d/ /etc/cont-init.d/

RUN /command/s6-rc-compile /etc/s6-overlay/s6-rc-compiled /etc/s6-overlay/s6-rc.d

ENV S6_CMD_WAIT_FOR_SERVICES=1
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=30000
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

# Switch to agent user for agent-owned config initialization
USER agent

ENV SHELL=/usr/bin/zsh
ENV HOME=/home/agent
ENV USER=agent
ENV LOGNAME=agent

ENV PATH="${PATH}:/home/agent/.dotnet/tools"

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

WORKDIR /home/agent/workspace

EXPOSE 2222

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD bash -c 'echo > /dev/tcp/127.0.0.1/2222' || exit 1

# s6 init must run as root so dockerd and sshd can start properly
USER root

ENV DOCKER_HOST=unix:///var/run/docker.sock

ENTRYPOINT ["/init"]
