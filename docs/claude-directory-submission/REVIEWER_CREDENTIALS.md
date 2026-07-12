# Claude Directory — Reviewer Test Account

These credentials are for the Anthropic reviewer to test the BioMate connector.
Share these when you complete the submission form.

> ⚠️  This is a **dev account** on `dev-public.biomate.ai`.
> Trial expires **2026-07-26**. Extend or recreate before sharing with Anthropic.
> Do not commit this file to a public repository.

## Account

| Field | Value |
|-------|-------|
| Surface | `https://dev-public.biomate.ai` |
| Email | `reviewer@biomate.ai` |
| Password | `BioMateReview2026!` |
| Plan | Professional (trial, 14 days from 2026-07-12) |
| Account ID | `096dff7d-02fb-4c81-a8fa-44a2be40388c` |

## API Key

```
bm_live_zTKrjJi6_wa5QNkt3LeUUhpPGx6zJ8px
```

**Key name:** Claude Directory reviewer key  
**Key ID:** `405d7c66-4ebe-461a-ab37-10a4c883f985`  
**Created:** 2026-07-12

Pass it as:
```
Authorization: Bearer bm_live_zTKrjJi6_wa5QNkt3LeUUhpPGx6zJ8px
```
or as the `BIOMATE_API_KEY` environment variable.

## Claude Code setup for reviewer

Add to `~/.claude.json`:

```json
{
  "mcpServers": {
    "biomate": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@biomate/mcp-server"],
      "env": {
        "BIOMATE_API_KEY": "bm_live_zTKrjJi6_wa5QNkt3LeUUhpPGx6zJ8px",
        "BIOMATE_API_URL": "https://dev-public.biomate.ai"
      }
    }
  }
}
```

## Test prompts for the reviewer

```
Search BioMate for RNA-seq differential expression workflows.
```

```
What ADMET prediction workflows are available? Show me parameters for the top one.
```

```
List my recent runs.
```

## MCP endpoint note

The HTTP/REST MCP transport (`POST /mcp`) is not yet deployed as a standalone
service. The current entry point for Claude Code is the stdio server above.
To enable ChatGPT and REST-based surfaces, `biomate-connector/mcp/biomate_http_server.py`
needs to run as a persistent process behind nginx on a public hostname.
