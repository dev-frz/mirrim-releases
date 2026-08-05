<p align="center"><strong>otto</strong></p>

# Otto — a personal AI agent that's actually *yours*

Otto is an AI assistant that lives on **your** computer instead of somebody
else's cloud. It remembers what matters to you, works on things while you're
away, and reaches you wherever you already are — your browser, your phone,
Telegram, even out loud. And because it runs on your own machine, your
conversations, notes, and memories stay in one file you can copy, back up, or
delete whenever you like.

Think of it less like a chatbot and more like a quietly competent assistant who
keeps a notebook, watches the things you asked it to watch, and taps you on the
shoulder only when something needs you.

## Why otto?

- **It's yours.** Everything otto knows lives in a single database file on your
  computer — no account, no subscription to this project, no lock-in. Use
  Claude for the smartest experience, or pair otto with a **free local model**
  (Ollama, LM Studio, and friends) so even the AI itself runs on your hardware.
- **It's light.** The entire agent is one 54 MB self-contained binary that
  idles at roughly 240 MB of RAM in a single process — no Docker stack, no
  vector-database or browser sidecars. A fresh database starts under 2 MB, and
  every table has an explicit retention policy, so storage stays flat after
  years of daily use, not just on day one.
- **It remembers.** Otto keeps long-term memory across every conversation,
  maintains a living notebook — one organized page per person, project, and
  topic in your life (readable and editable as plain Markdown, Obsidian-friendly)
  — and builds a picture of how you like to work.
- **It acts on its own — carefully.** Reminders, recurring routines, watched
  inboxes and calendars, long research jobs that report back when done. Before
  doing anything with side effects, it **asks you first**.
- **It earns trust instead of assuming it.** Every action lands in a
  tamper-evident audit ledger you can verify. API keys go in an encrypted vault
  the AI can use but never read. Nothing is silently deleted.
- **It meets you anywhere.** A polished web console (installable as an app,
  with push notifications), Telegram (text, photos, voice notes), Discord,
  desktop notifications — and full hands-free voice conversation, interruptions
  included.

## Get started in about two minutes

One command installs otto and keeps it running in the background — through
reboots, forever — on Linux, macOS, or Windows:

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/ferozhussain/otto-releases/main/install.sh | bash

# Windows (PowerShell)
irm https://raw.githubusercontent.com/ferozhussain/otto-releases/main/install.ps1 | iex
```

Then open **http://localhost:5080** in your browser and follow the setup page:
pick your AI provider (an Anthropic key for Claude, an OpenRouter key, or a
free local model — no key at all), and start talking.

Uninstalling is one command too, and your data is kept unless you say
otherwise. Prefer Docker, a headless server, or building from source? See
**[Getting started](docs/getting-started.md)** for every path.

## What can you ask it?

> "Remind me every Monday at 9 to send the weekly invoice."

> "Watch my inbox and nudge me if anything urgent shows up."

> "Research standing-desk options under $400 and write me a comparison —
> take your time, I'll be in a meeting."

> "What did we decide about the kitchen renovation last month?"

Or send it a photo of a document on Telegram, a voice note while walking, or
just talk to it hands-free in the console. It schedules real background work,
checks its own notes, and messages you proactively with results — escalating
politely if something important goes unread.

This repository is the **public download & install channel**: it contains no
source code — only the installers below and the published build artifacts under
[**Releases**](https://github.com/ferozhussain/otto-releases/releases). Each
release ships self-contained bundles for Linux, macOS, and Windows, plus
SHA-256 checksums and an SBOM.


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
