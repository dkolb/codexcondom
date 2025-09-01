ARG FEDORA_BASE=registry.fedoraproject.org/fedora:latest
ARG UID=1000
ARG GID=1000
ARG USERNAME=codex
FROM ${FEDORA_BASE}
ARG UID
ARG GID
ARG USERNAME

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN dnf -y upgrade --refresh && \
    dnf -y install \
      sudo \
      git \
      curl \
      wget \
      ca-certificates \
      python3 \
      python3-devel \
      python3-pip \
      pipx \
      nodejs \
      gcc \
      gcc-c++ \
      make \
      pkgconf-pkg-config \
      openssl-devel \
      which \
      shadow-utils && \
    dnf clean all && rm -rf /var/cache/dnf

# Create a non-root user matching host UID/GID so file ownership is consistent
RUN groupadd -g ${GID} ${USERNAME} && \
    useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME}

# Install Codex CLI globally so it is available to all users
RUN npm install -g @openai/codex || true

# Install uv and place the binary on PATH for all users
# The official installer drops uv into the invoking user's ~/.local/bin; move it system-wide.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/uv || true

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Default command: load interactive shell environment then exec codex
CMD ["bash", "-lc", "exec codex"]
