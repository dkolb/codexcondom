# Codex Condoms (Podman + Fedora)

Provision a reusable Fedora-based Podman environment per workspace with core development tools, Python with `uv`, and Node.js. Each workspace gets a deterministic environment name and its own home directory for clean isolation. A cached local image `localhost/codex:latest` reduces startup time for new workspaces.

## Features

- Per‑workspace home at `~/codex_condoms/{slug-hash}`
- Host home masked so only the dedicated home and explicit mounts are visible
- Deterministic environment name from workspace path (slug + short hash)
- Workspace mounted inside container at `$HOME/workspace`
- `~/.codex` mounted read‑write to preserve Codex auth and MCP configs (mounted inside as `$HOME/.codex`)
- Python 3 + build deps and `uv` (preinstalled in the image); Node.js + npm; common dev tools
- Agent context written to `$HOME/.config/codex/env` inside the container

## Requirements

- `podman`
- Internet access to build the base image

## Quick Start

Launch the environment for a workspace (image is built on first run):

```bash
codexcondom /abs/path/to/workspace
```

## Usage

```bash
codexcondom [/abs/path/to/workspace] [options]
```

Options:

- `--image IMG` — Base Fedora image for the cached build (default: `registry.fedoraproject.org/fedora:latest`)
- `--name NAME` — Override environment name
- `--recreate-container` — Recreate the environment (no image rebuild)
- `--rebuild-image` — Rebuild the cached image without cache
- `--recreate-homedir` — Wipe and recreate the per‑workspace home directory
- `--total-rebuild` — Same as `--rebuild-image --recreate-container --recreate-homedir`
- `--no-mask-host-home` — Do not mask the host home inside the container
- `--bash` — Start an interactive bash instead of codex

Examples:

```bash
# Open a bash shell instead of codex
codexcondom /abs/path --bash

# Rebuild the base image from scratch (on next run)
codexcondom /abs/path --rebuild-image

# Fully reset everything for this workspace before launching
codexcondom /abs/path --total-rebuild
```

## What Gets Provisioned

- Environment name derived from the workspace path
- Per‑workspace home at `~/codex_condoms/{slug-hash}` with the host home masked
- Mounts:
  - Workspace → `$HOME/workspace` (read-write with matching UID/GID)
  - `~/.codex` → `$HOME/.codex` (read‑write; created on host if missing)
- Cached image preinstalls dev packages, Python, and Node.js
- `uv` is preinstalled and available on PATH as `uv`
- Writes agent context to `$HOME/.config/codex/env`

## Install (brief)

One-liner (non-interactive):

```bash
curl -fsSL https://raw.githubusercontent.com/dkolb/codex-condom/main/install.sh | bash
```

Or from a cloned repo:

```bash
./install.sh
```

- Installs `codexcondom` to `~/.local/bin` under your home (or `/root` if run as root)
- Copies runtime Containerfile into `~/.local/share/codexcondoms/`
- Prompts to add `~/.local/bin` to PATH when interactive; warns otherwise if missing

## Security Note

This environment intentionally does not mount the host Docker socket. Running Docker commands inside the container is not supported to reduce risk.

## Python, uv, and Node.js

- Python 3 and common build dependencies are installed in the base image
- `uv` is preinstalled and available on PATH as `uv`
- Node.js and npm come from Fedora packages (version depends on image)

## Mounting `~/.codex`

`~/.codex` is always mounted read‑write and created on the host if missing. This ensures Codex can sign in, refresh tokens, and persist MCP configuration across sessions.

## Inside the Container

- Workspace root: `$HOME/workspace`
- Agent env file: `$HOME/.config/codex/env` (key=value lines)
  - Includes: `CODEX_CONTAINER_NAME`, `CODEX_HOME`, `CODEX_WORKSPACE_DIR`
  - A symlink `$HOME/.codex` → `$HOME/.config/codex` is present for legacy tooling

Debugging:

- Set `CODEX_CONDOM_DEBUG=1` to enable verbose logs and `podman` output

<!-- distrobox.ini is no longer used in this workflow. -->

## Troubleshooting

- SELinux: `:z` is applied to workspace and `.codex` mounts for compatibility
- Versions: Python/Node versions track the Fedora image; pin specific versions as needed

## Cleanup

Remove the persistent container and the per‑workspace home:

```bash
podman rm -f <environment-name>
rm -rf ~/codex_condoms/{slug-hash}
```
