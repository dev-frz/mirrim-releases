<p align="center"><strong>otto</strong></p>

# Otto — a personal AI agent that's actually *yours*

Otto is an AI assistant that lives on **your** computer instead of somebody
else's cloud. It remembers what matters to you, works on things while you're
away, and reaches you wherever you already are — your browser, your phone,
Telegram, even out loud. Everything it knows lives in one database file on
your machine that you can copy, back up, or delete whenever you like.

- **It's yours.** No account, no subscription to this project, no lock-in.
  Use Claude for the smartest experience, or pair otto with a **free local
  model** (Ollama, LM Studio, and friends) so even the AI runs on your hardware.
- **It's light.** The entire agent installs as a single self-contained binary
  (about 55 MB, no .NET runtime required) and runs as one process in a few
  hundred megabytes of RAM — no Docker stack, no vector-database or browser
  sidecars. A fresh database starts under 2 MB, and built-in retention policies
  keep storage flat after years of daily use.
- **It remembers.** Long-term memory across every conversation, plus a living
  notebook — one organized page per person, project, and topic in your life,
  readable and editable as plain Markdown.
- **It acts on its own — carefully.** Reminders, recurring routines, watched
  inboxes and calendars, long research jobs that report back when done. Before
  doing anything with side effects, it **asks you first**.
- **It earns trust.** Every action lands in a tamper-evident audit ledger you
  can verify. API keys go in an encrypted vault the AI can use but never read.

This repository is the **public download & install channel**: it contains no
source code — only the installers below and the published build artifacts under
[**Releases**](https://github.com/dev-frz/otto-releases/releases). Each
release ships self-contained bundles for Linux, macOS, and Windows, plus
SHA-256 checksums and an SBOM.

## Install

**Linux / macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/dev-frz/otto-releases/main/install.sh | bash
```

**Windows (PowerShell)**

```powershell
irm https://raw.githubusercontent.com/dev-frz/otto-releases/main/install.ps1 | iex
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
finish setup in the browser — pick a provider and paste your key (or choose a
local model and skip keys entirely). On a headless box run `otto setup` in the
terminal instead.

## Uninstall

Stops and removes the service, the PATH entry, and the binary. Your data
(`.env`, `agent.db`) is kept unless you pass `--purge` / `-Purge`.

**Linux / macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/dev-frz/otto-releases/main/uninstall.sh | bash
```

**Windows (PowerShell)**

```powershell
iwr https://raw.githubusercontent.com/dev-frz/otto-releases/main/uninstall.ps1 -OutFile uninstall.ps1; ./uninstall.ps1
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
[latest release](https://github.com/dev-frz/otto-releases/releases/latest):

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
