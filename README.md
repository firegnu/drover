# drover

> **Retired — historical archive (2026-09-30).** Drover now lives entirely in the [Saddle Drover plugin](https://github.com/firegnu/saddle/tree/main/plugins/drover), including task management, storage, UI, state transitions and notifications. Follow the [plugin usage guide](https://github.com/firegnu/saddle/blob/main/plugins/drover/README.md). Its lifecycle follows Saddle; do not install this repository's standalone CLI or launchd/watch service. The instructions below describe historical versions. Keep existing local repositories, project registration and task data; archiving this repository does not remove them.

English | [简体中文](README.zh-CN.md)

Track one task at a time: explicitly dispatch it, submit its delivery for review, and record the user's acceptance.

## Responsibilities

- Corral provides agent infrastructure; Drover only uses its public send/status/ls commands.
- The coordinating agent handles development, review, merging and worktree cleanup.
- Drover records Pending → Running → Awaiting release → Done and observes new submissions for notifications.
- The user accepts deliveries. Git and test evidence are reference information, not universal state gates.

`done` explicitly submits; `go` only accepts an Awaiting delivery. Neither dispatches the next task. Running and Awaiting tasks may return to Pending while retaining their work and previous submissions. Serial scheduling remains unchanged.

The existing curses board uses the same core and observed action tokens: `d` submits, `g` accepts, `n` explicitly dispatches the first Pending task. `notifications watch` is an independent observer, with no automatic completion or dispatch behavior.

See [Quickstart](docs/QUICKSTART.md) and [task API v2 / coordinated release instructions](docs/任务流转JSON接口.md). Old next/loop/hold/complete-manually paths are retired. This branch awaits review and coordinated Saddle integration; do not deploy it separately. Worktree development/review/merge/cleanup remains unchanged.

## Origins

drover was cloned from [herdsman / bounded-adversarial-review](https://github.com/firegnu/herdsman), with its full history preserved. That project ran on herdr: one agent implemented changes, and another reviewed them.

Once corral and corral-dispatch existed, the inner loop could handle reviews with a lighter workflow. What remained distinctive about herdsman was its queue, dashboard, and task accounting—the outer loop. This repository's first commit therefore removed the review protocol (`4545f68`) and kept the outer loop.

The old repository is frozen and no longer maintained. Its design history remains available in `git log`.

## Status

The explicit lifecycle redesign is implemented on a review branch. Existing task events are decoded without rewriting historical facts. No real queue, CLI installation, or running service is changed by development.

## Requirements

- [corral](https://github.com/firegnu/corral)
- `python3` (standard library only)
- `git`

## Installation (with human approval)

Run `sh ./install.sh` from a repository checkout you intend to keep. The script installs `drover` and `drover-board` as absolute symbolic links in `~/.local/bin/`, creates `~/.drover/`, and generates `~/.drover/dev.drover.loop.plist`. Repository updates take effect directly. Do not install from a temporary worktree that will later be deleted; moving the checkout also breaks the links.

Before writing anything, the installer checks every destination. Existing command links are accepted only if they point to this checkout; an existing generated plist must be a regular file with identical contents. Otherwise, installation exits with a nonzero status and refuses to overwrite anything. Reinstalling with the same configuration does not rewrite files. If `~/.local/bin` is missing from PATH, the installer asks you to add it yourself; it does not edit shell configuration.

The installer fills in `__HOME__` and `__PATH__` in the launchd template and XML-escapes their values. Do not load the repository's template directly. The generated file records the expanded HOME and uses this fixed service PATH: `<HOME>/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`. It does not copy your terminal's PATH. Unrelated changes to the terminal PATH will not prevent reinstallation or add temporary Python directories to the service PATH. The installer itself still uses python3 from the terminal PATH. If an old plist differs from the generated content, the installer refuses to overwrite it; inspect and resolve the difference manually.

Before enabling the service, confirm that these fixed directories provide `python3`, `git`, `corral`, its runtime, and any the notification sender. Custom environments outside these directories are not supported automatically. Successful installation does not guarantee that the background service can run.

**The script does not run launchctl or write to `~/Library/LaunchAgents/`.** It only prints commands for manual activation: link the generated file into that directory and load the observer as `dev.drover.loop`. Activation starts `drover notifications watch` immediately; it starts again on subsequent logins and restarts if it exits. A user LaunchAgent does not start before login. Standard output and errors go to `~/.drover/loop.stdout.log` and `~/.drover/loop.stderr.log`. If the destination already exists or the service is already loaded, inspect it first instead of overwriting or loading it again.

In the target project, run `drover init <short-name>`, configure MAIN_AGENT, and add tasks to queue.md. Use the explicit token-based task API. To observe submissions, run `drover notifications watch` (60 seconds by default) or enable the generated LaunchAgent after approval. Do not run both.

For an upgrade, stop the old KeepAlive progression engine **before** switching the CLI and Saddle together. The retained `dev.drover.loop` service label is only a deployment identity; the new template runs the notification observer. Existing different plists are deliberately not overwritten by the installer.

Isolated validation: `sh tests/install.sh` (macOS, a temporary HOME and a write sandbox; it does not invoke the real launchctl).
