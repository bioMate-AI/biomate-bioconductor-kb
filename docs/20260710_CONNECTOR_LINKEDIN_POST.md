We just open-sourced the BioMate connector layer — one codebase that wires Claude Code, Claude Science, Codex CLI, ChatGPT, Slack, and Feishu to the same bioinformatics execution engine.

Here's the architecture in one sentence: a single tool manifest (tools_manifest.py) defines 19 tools once. Every AI surface reads its schema from that file and routes calls through the same dispatch function. No duplicated logic across six integrations.

What the tools do:
→ biomate_session: natural language → workflow → AWS Batch → findings (the only tool most users need)
→ search_literature: iterative depth-loop across PubMed, EuropePMC, Semantic Scholar, OpenAlex
→ query_database: federated fan-out to UniProt, PDB, NCBI Gene, ClinVar, gnomAD, KEGG, ChEMBL
→ run_workflow + watch_run: execute one of 2,455 indexed pipelines (DESeq2, nf-core/sarek, AlphaFold, CryoSPARC, ADMET, PBPK) and stream live phase updates back to the AI

The transports are the interesting part:

Claude Code / Codex → stdio JSON-RPC, zero infrastructure, two-line config
Claude Science → Streamable HTTP + OAuth 2.1 + PKCE (required HTTPS even on localhost — yes, we had to auto-generate a self-signed cert)
ChatGPT → REST Actions with a thin Flask adapter that polls async workflows to completion before returning (ChatGPT has no streaming transport)
Slack / Feishu → webhook adapters that stream Batch job updates into threaded replies

The remote MCP endpoint (mcp.stage-public.biomate.ai) runs on AWS with full Dynamic Client Registration, per-user encrypted API keys, and RFC 9728 resource metadata — so any MCP-compliant client that supports OAuth can connect without any local install.

Fully open source, MIT licensed.

Repo: github.com/bioMate-AI/biomate-connector
Full architecture writeup: [blog link]

If you're building AI tooling for wet-lab or computational biology teams, I'd love to hear what workflows you'd want to expose this way. Drop a comment or DM.

#bioinformatics #MCP #AItools #openSource #lifesciences #claudeAI #ChatGPT
