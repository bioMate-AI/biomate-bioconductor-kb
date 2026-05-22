# BioMate × OpenAI Codex CLI

> Run real bioinformatics from the Codex CLI. Tool calls return progress events as a delta list (Codex doesn't render rich progress UI), so the model loops on `poll_run` for live updates.

## Install (30 seconds)

```bash
npx @biomate/connect codex
```

This writes the BioMate MCP entry to `~/.codex/config.toml`. Restart `codex` to pick up the new server.

## Try it

```bash
codex "Screen the compounds in compounds.smi for hERG and CYP3A4 inhibition. Use BioMate."
```

```bash
codex "Run RNA-seq DE on the FASTQs in s3://lab/rnaseq/, treated vs control, GRCh38."
```

Codex prefers terse interactions — BioMate's `biomate_session` returns a markdown summary + deep link on each progress event, which Codex displays inline. For long runs the model polls `poll_run` automatically.

## Manual config

`~/.codex/config.toml`:

```toml
[mcp_servers.biomate]
command = "npx"
args = ["-y", "@biomate/mcp-server"]

[mcp_servers.biomate.env]
BIOMATE_API_BASE = "https://api.biomate.ai"
BIOMATE_REFRESH_TOKEN = "<your-refresh-token>"
```

Refresh token: https://biomate.ai/account/connectors/codex.

## Tools available

Same 14-tool surface as the Claude Code integration. See [`../claude-code/README.md`](../claude-code/README.md).

## Streaming on a non-streaming surface

Codex CLI doesn't render MCP `notifications/progress` like Claude Code does. BioMate exposes a paired `poll_run(run_id, since_event_id)` tool that returns the same event payloads as a delta list — the model loops on it. Same backend code path, same event shape.

## License

MIT.
