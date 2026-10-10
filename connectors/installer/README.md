# @biomate/connect

> One-line installer that wires BioMate AI into Claude Code, Claude Desktop, Cursor, OpenAI Codex, ChatGPT, and Open Claw (WeChat).

Real bioinformatics — `nf-core/sarek`, CryoSPARC, AlphaFold, ADMET screens, PBPK — runs from your favorite AI coding assistant. No SaaS lock-in: tokens are stored locally in a protected credential file.

## Install

```bash
# Connect Claude Code
npx @biomate/connect claude-code

# Connect Cursor
npx @biomate/connect cursor

# Connect Codex CLI
npx @biomate/connect codex
```

The CLI opens your browser for OAuth with PKCE and writes the MCP configuration. Version 0.1.1 stores rotating tokens in a mode-0600 file under `~/.config/biomate/`; host configurations contain only its path. This release defaults explicitly to the verified development deployment at `https://dev-public.biomate.ai`; use `--auth-base` to select a different deployed server. Existing OAuth installations must reconnect with the updated installer.

## Supported surfaces

| Surface | Install command | Config file written |
|---|---|---|
| Claude Code | `npx @biomate/connect claude-code` | `~/.claude.json` |
| Claude Desktop | `npx @biomate/connect claude-desktop` | `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) |
| Cursor | `npx @biomate/connect cursor` | `~/.cursor/mcp.json` |
| Codex CLI | `npx @biomate/connect codex` | `~/.codex/config.toml` |
| ChatGPT | `npx @biomate/connect chatgpt` | (Custom GPT — instructions printed) |
| Open Claw | `npx @biomate/connect open-claw` | (hosted webhook — account linked) |

## What you get

After connecting, your AI assistant has access to BioMate's 19-tool MCP surface:

- **`biomate_session`** — natural-language goal → analysis plan, workflow suggestions and clarification requests; review the plan before execution
- **`search_workflow`** + **`get_workflow_spec`** — discover workflows in the catalog
- **`run_workflow`** + **`get_run`** + **`watch_run`** + **`cancel_run`** — launch, cancel and poll run status (snapshot updates)
- **`preview_file`**, **`export_report`**, **`analyze_results`**, **`explain_error`**, **`query_database`**, **`resolve_accession`**, **`browse_data`**, **`fetch_public_data`**, **`search_literature`**, **`recall_memory`**, **`upload_file`**

## Try it

Open your assistant and paste:

```
Screen aspirin and caffeine for hERG and CYP3A4 inhibition.
```

```
Run RNA-seq differential expression on these FASTQs:
  s3://biomate-demo/sample_R1.fq.gz, s3://biomate-demo/sample_R2.fq.gz
Compare treated vs control.
```

```
Look up UniProt P04637.
```

## Privacy & security

- OAuth with PKCE; access tokens carry permission scopes enforced by
  the OAuth service; access is also blocked when the associated personal API key is revoked
- Server-side refresh-token records are hashed; local credential files contain secrets and must stay private
- Access tokens are 30-minute JWTs; refresh tokens rotate on use (OAuth 2.1 §6.1)
- No telemetry beyond standard API logs

## Development

```bash
npm install
npm run build
npm test
```

## License

MIT

## Supported exports

This package exports Markdown findings reports. PDF, DOCX, other report sections, instrument tools and MCP progress notifications are not advertised by the 0.1.1 stdio package. ChatGPT Actions and hosted WeChat setup are separate integrations and are not validated by the desktop installer tests.
