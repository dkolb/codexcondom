**Codex Condoms + Agents Context**
- **Containerized Workspace:** Agents run inside a Fedora-based Podman container that mounts the active workspace at `$HOME/workspace` and sets container home to a unique path under `~/codex_condoms/`.
- **Environment File:** Read key runtime values from `$HOME/.config/codex/env`:
  - `CODEX_CONTAINER_NAME` — current environment name
  - `CODEX_HOME` — container home path (host bind)
  - `CODEX_WORKSPACE_DIR` — absolute path to the mounted workspace
  
Security: Docker socket is not mounted; running Docker inside the container is unsupported.

Config directory: Host `~/.codex` is mounted read‑write at `$HOME/.codex`.

Quick load example (bash/sh):

```bash
set -a
. "$HOME/.config/codex/env" 2>/dev/null || true
set +a
```

**Docker:** Not available in-container. Do not attempt to use the host Docker socket.

**Auth and MCP Configs (`~/.codex`)**
- The host `~/.codex` is mounted into the container read‑write and created if missing. Tokens and MCP configs persist across sessions.

**Installed Tooling**
- **Python:** `python3` with build deps; `uv` available on PATH.
- **Node.js:** `node` and `npm` via Fedora packages.
- **Dev Tools:** compilers, make, pkg-config, git, curl, wget, etc.

Notes:
- `uv` is preinstalled in the base image and available as `uv` on PATH.
 - Launcher is `codexcondom` (single command; no subcommands). Use `--bash` to enter a shell instead of running `codex`.

**Paths & Conventions**
- **Workspace:** `$HOME/workspace` is the canonical workspace root.
- **Logs/State:** `~/.codex` is mounted read‑write; prefer project-local files for app data where possible.
- **Home Masking:** Host home is masked by default; only `$HOME` and explicit mounts are visible.

**Repro & Reuse**
- Environment names are derived deterministically from the workspace path (slug + short hash).
- A cached local image `localhost/codex:latest` speeds up provisioning; rebuild with `--rebuild-image` (or `--total-rebuild`).
