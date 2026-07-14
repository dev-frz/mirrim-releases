# self-assist — releases

Public download & install channel for **self-assist**, a local-first personal AI
agent that runs 24/7 on your own machine (Claude or a local model as the
backbone; Telegram + a web console as the interface).

This repository contains **no source code** — only the installers below and the
published build artifacts under [**Releases**](https://github.com/ferozhussain/self-assist-releases/releases).
Each release ships self-contained bundles (no .NET runtime required) for Linux,
macOS, and Windows, plus SHA-256 checksums and an SBOM.

## Install

**Linux / macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/ferozhussain/self-assist-releases/main/install.sh | bash
```

**Windows (PowerShell)**

```powershell
irm https://raw.githubusercontent.com/ferozhussain/self-assist-releases/main/install.ps1 | iex
```

The installer downloads the right build for your OS/arch, installs it per-user,
and registers a managed 24/7 service — `systemd --user` on Linux, a `launchd`
LaunchAgent on macOS, a Scheduled Task on Windows. Re-running upgrades the binary
in place and keeps your data (`.env`, `agent.db`).

After the first install, set your key and open the console:

1. Edit the `.env` in your data directory (`~/.local/share/self-assist/data/.env`
   on Linux/macOS, `%LOCALAPPDATA%\self-assist\data\.env` on Windows) — set
   `ANTHROPIC_API_KEY`, or `Llm__Provider=Local` to use a local model.
2. Restart the service.
3. Open <http://localhost:5080>.

## Options

- **Pin a version** — install a specific release instead of the latest:
  `SELF_ASSIST_VERSION=v1.2.3` (bash) or `$env:SELF_ASSIST_VERSION = "v1.2.3"`
  (PowerShell) before running the installer.
- **Custom install location** — `SELF_ASSIST_HOME=/path` / `$env:SELF_ASSIST_HOME`.
- **API rate limits** — installing needs no token. Optionally set `GITHUB_TOKEN`
  to lift GitHub's unauthenticated API rate limit on the "latest release" lookup.

## Manual download

Prefer to install by hand? Grab the asset for your platform from the
[latest release](https://github.com/ferozhussain/self-assist-releases/releases/latest):

| Platform            | Asset                                   |
| ------------------- | --------------------------------------- |
| Linux x64           | `self-assist-<version>-linux-x64.tar.gz`   |
| Linux arm64         | `self-assist-<version>-linux-arm64.tar.gz` |
| macOS x64 (Intel)   | `self-assist-<version>-osx-x64.tar.gz`     |
| macOS arm64 (Apple) | `self-assist-<version>-osx-arm64.tar.gz`   |
| Windows x64         | `self-assist-<version>-win-x64.zip`        |

Verify against `SHA256SUMS` (attached to each release), extract, and run the
`self-assist` executable.

## Verify a download

```bash
sha256sum -c SHA256SUMS --ignore-missing
```
