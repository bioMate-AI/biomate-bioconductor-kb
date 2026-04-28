# Claude Code Mobile Session Sharing

**Date:** 2026-04-26

## Problem

Claude Code runs on a desktop. There is no built-in feature to join the same interactive session from a phone or second device.

## Solution: tmux + SSH (+ Tailscale for remote networks)

### Step 1 — Start Claude Code inside tmux on the desktop

```bash
tmux new -s claude
claude
```

This creates a named tmux session called `claude`. Claude Code runs inside it.

### Step 2 — SSH from your phone and attach

```bash
ssh user@your-desktop-ip
tmux attach -t claude
```

Both devices now share the exact same terminal session. Input from either side is reflected on both.

### Step 3 (remote networks only) — Tailscale

If the desktop and phone are on different networks (e.g. desktop at home, phone on cellular):

1. Install [Tailscale](https://tailscale.com) on both the desktop and the phone.
2. Sign in with the same account on both.
3. SSH using the Tailscale hostname instead of a LAN IP:

```bash
ssh user@your-machine-name
tmux attach -t claude
```

Tailscale is free for personal use and handles NAT traversal automatically.

## Phone SSH Apps

| Platform | Recommended Apps |
|----------|-----------------|
| iOS | Blink Shell, Termius |
| Android | JuiceSSH, Termius |

## Managing Multiple Claude Sessions

If you have several Claude Code sessions running simultaneously, name each tmux session descriptively:

```bash
tmux new -s admet-run
tmux new -s cryo-debug
tmux new -s billing-fix
```

**From your phone — list and pick a session:**
```bash
ssh user@desktop
tmux ls
# admet-run:  1 windows (created ...)
# cryo-debug: 1 windows (created ...)
# billing-fix: 1 windows (created ...)

tmux attach -t cryo-debug
```

**Switching between sessions without disconnecting:**
- `Ctrl-b s` — interactive list of all sessions; arrow keys to select
- `Ctrl-b $` — rename the current session

## Notes

- `tmux ls` lists all active sessions if you forget the session name.
- `tmux attach` (no `-t`) attaches to the most recent session.
- Detach from the session on either device with `Ctrl-b d` — the session keeps running.
- Claude Code itself has no native cross-device pairing or session-sharing feature.
