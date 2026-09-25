# drover

English | [简体中文](README.zh-CN.md)

Feed a task queue to a coordinating agent, one task at a time, and keep work moving while you are away.

A drover guides livestock over long distances: it does not choose the destination; it keeps the herd moving.

## Three layers

| Layer | Role | What it knows about | Timescale |
|---|---|---|---|
| [corral](https://github.com/firegnu/corral) | Infrastructure | Starting agents, sending messages, and checking status. No workflow knowledge. | Process lifetime |
| corral-dispatch (a skill in the corral repository) | **Inner loop** | corral commands; how to split work, assign it, and review it | Minutes to hours, with the coordinator present |
| **drover** | **Outer loop** | corral commands; queues, gates, when to wake the coordinator, and task accounting | Days, unattended |

**Dependencies only point downward.** drover depends so little on the inner loop that it also works for projects where a person drives that loop manually.

## What it does

1. Sends the task body to the coordinator.
2. Performs read-only Git checks to determine whether the work is complete.

Those are its only two actions. **It never starts, stops, or attaches to an agent**—people handle that. It uses only three corral commands: `send`, `status`, and `ls`.

A dark terminal dashboard (curses TUI) shows the queue, the current task's progress and completion criteria, and when you need to act. Its view is read-only; keys invoke task operations: `g` verifies completion, records it, and releases the task; `n` sends the next task; `p` pauses the queue; and `a` opens an editor to add tasks. For a task already recorded as complete, `g` only releases it. The `g` key never sends the next task itself; when the loop is enabled, the engine handles that.

## What it does not do

- Define a review protocol, track findings or review rounds, or impose evidence requirements (those belonged to its predecessor, below).
- Start, stop, or attach to agents, or automatically restart the coordinator.
- Parse the coordinator's natural-language conclusions.
- Read corral's internal files, or install, upgrade, or manage corral.
- Change corral or corral-dispatch to meet its own needs.

## Origins

drover was cloned from [herdsman / bounded-adversarial-review](https://github.com/firegnu/herdsman), with its full history preserved. That project ran on herdr: one agent implemented changes, and another reviewed them.

Once corral and corral-dispatch existed, the inner loop could handle reviews with a lighter workflow. What remained distinctive about herdsman was its queue, dashboard, and task accounting—the outer loop. This repository's first commit therefore removed the review protocol (`4545f68`) and kept the outer loop.

The old repository is frozen and no longer maintained. Its design history remains available in `git log`.

## Status

**Under development.** The review protocol has been removed. Configuration, completion criteria, corral transport, the dashboard, and the outer loop are implemented (D1 steps 0–4). The scripts are exposed through a single `drover` command. Completion detection has an explicit basis: a wrap-up commit marker. The loop engine runs independently as `drover loop`, separate from the dashboard.

**D1 is complete.** The installation script and launchd template are ready; **actual installation and activation require human approval**. Next is D2 validation: layer 1 (synthetic tests) was completed alongside D1; self-hosting and sandbox validation remain.

The following guides are in Chinese:

- Installation and usage: [docs/QUICKSTART.md](docs/QUICKSTART.md)
- Design rationale and troubleshooting: [docs/手册.md](docs/手册.md)
- Design and implementation stages: [docs/ROADMAP.md](docs/ROADMAP.md)
- Repository working rules: [AGENTS.md](AGENTS.md)

## Requirements

- [corral](https://github.com/firegnu/corral)
- `python3` (standard library only)
- `git`

## Installation (with human approval)

Run `sh ./install.sh` from a repository checkout you intend to keep. The script installs `drover` and `drover-board` as absolute symbolic links in `~/.local/bin/`, creates `~/.drover/`, and generates `~/.drover/dev.drover.loop.plist`. Repository updates take effect directly. Do not install from a temporary worktree that will later be deleted; moving the checkout also breaks the links.

Before writing anything, the installer checks every destination. Existing command links are accepted only if they point to this checkout; an existing generated plist must be a regular file with identical contents. Otherwise, installation exits with a nonzero status and refuses to overwrite anything. Reinstalling with the same configuration does not rewrite files. If `~/.local/bin` is missing from PATH, the installer asks you to add it yourself; it does not edit shell configuration.

The installer fills in `__HOME__` and `__PATH__` in the launchd template and XML-escapes their values. Do not load the repository's template directly. The generated file records the expanded HOME and uses this fixed service PATH: `<HOME>/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`. It does not copy your terminal's PATH. Unrelated changes to the terminal PATH will not prevent reinstallation or add temporary Python directories to the service PATH. The installer itself still uses python3 from the terminal PATH. If an old plist differs from the generated content, the installer refuses to overwrite it; inspect and resolve the difference manually.

Before enabling the service, confirm that these fixed directories provide `python3`, `git`, `corral`, its runtime, and any tools required by your acceptance command. Custom environments outside these directories are not supported automatically. Successful installation does not guarantee that the background service can run.

**The script does not run launchctl or write to `~/Library/LaunchAgents/`.** It only prints commands for manual activation: link the generated file into that directory and load the engine as `dev.drover.loop`. Activation starts `drover loop` immediately; it starts again on subsequent logins and restarts if it exits. A user LaunchAgent does not start before login. Standard output and errors go to `~/.drover/loop.stdout.log` and `~/.drover/loop.stderr.log`. If the destination already exists or the service is already loaded, inspect it first instead of overwriting or loading it again.

In the target project, run `drover init <short-name>`, configure the coordinator in `.drover.conf`, write tasks to `queue.md` in the handoff directory, and run `drover loop on` to enable that project. Without launchd, run `drover loop` in another terminal (it checks every five seconds by default). Once launchd is enabled, do not start a second engine manually. Open the dashboard separately.

Isolated validation: `sh tests/install.sh` (macOS, a temporary HOME and a write sandbox; it does not invoke the real launchctl).
