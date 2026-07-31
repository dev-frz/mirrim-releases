# otto — releases

Public download & install channel for **otto**, a local-first personal AI
agent that runs 24/7 on your own machine (Claude or a local model as the
backbone; Telegram + a web console as the interface).

This repository contains **no source code** — only the installers below and the
published build artifacts under [**Releases**](https://github.com/ferozhussain/otto-releases/releases).
Each release ships self-contained bundles (no .NET runtime required) for Linux,
macOS, and Windows, plus SHA-256 checksums and an SBOM.

## Install

**Linux / macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/ferozhussain/otto-releases/main/install.sh | bash
```

**Windows (PowerShell)**

```powershell
irm https://raw.githubusercontent.com/ferozhussain/otto-releases/main/install.ps1 | iex
```

The installer downloads the right build for your OS/arch, verifies it against
the release's `SHA256SUMS`, installs it per-user, and registers a managed 24/7
service — `systemd --user` on Linux, a `launchd` LaunchAgent on macOS, and on
Windows a **background** Scheduled Task (no terminal window; a watchdog trigger
restarts it if it ever stops). On a first install it asks which port the web
console should use (default 5080) and whether to expose the console to your
local network (default no; a sign-in token is generated when you say yes).
Re-running upgrades the binary in place and keeps your data and settings
(`.env`, `agent.db`).

After the first install, open <http://localhost:5080> (or your chosen port) and
finish setup in the browser — pick a provider and paste your key. On a headless
box run `otto setup` in the terminal instead.

## Uninstall

Stops and removes the service, the PATH entry, and the binary. Your data
(`.env`, `agent.db`) is kept unless you pass `--purge` / `-Purge`.

**Linux / macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/ferozhussain/otto-releases/main/uninstall.sh | bash
```

**Windows (PowerShell)**

```powershell
iwr https://raw.githubusercontent.com/ferozhussain/otto-releases/main/uninstall.ps1 -OutFile uninstall.ps1; ./uninstall.ps1
```

## Options

- **Pin a version** — install a specific release instead of the latest:
  `OTTO_VERSION=v1.2.3` (bash) or `$env:OTTO_VERSION = "v1.2.3"`
  (PowerShell) before running the installer.
- **Custom install location** — `OTTO_HOME=/path` / `$env:OTTO_HOME`.
- **Scripted answers** — preset the first-install questions with
  `OTTO_PORT=5080` and `OTTO_EXPOSE_LAN=true|false` (bash) or
  `$env:OTTO_PORT` / `$env:OTTO_EXPOSE_LAN` (PowerShell). These also work on
  re-runs to change the settings of an existing install.
- **API rate limits** — installing needs no token. Optionally set `GITHUB_TOKEN`
  to lift GitHub's unauthenticated API rate limit on the "latest release" lookup.

## Manual download

Prefer to install by hand? Grab the asset for your platform from the
[latest release](https://github.com/ferozhussain/otto-releases/releases/latest):

| Platform            | Asset                                   |
| ------------------- | --------------------------------------- |
| Linux x64           | `otto-<version>-linux-x64.tar.gz`   |
| Linux arm64         | `otto-<version>-linux-arm64.tar.gz` |
| macOS x64 (Intel)   | `otto-<version>-osx-x64.tar.gz`     |
| macOS arm64 (Apple) | `otto-<version>-osx-arm64.tar.gz`   |
| Windows x64         | `otto-<version>-win-x64.zip`        |

Verify against `SHA256SUMS` (attached to each release), extract, and run the
`otto` executable.

## Verify a download

```bash
sha256sum -c SHA256SUMS --ignore-missing
```
