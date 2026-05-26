# Team brief — Designer + Marketer

**You own:** brand voice across 7 surfaces, demo recordings, landing page, blog/social copy, directory submissions.

## What's locked vs open

| Asset | Status | Where |
|---|---|---|
| Per-surface READMEs (8) | **Locked content; open polish** | `connectors/{claude-code,...,slack}/README.md` |
| Top-level connectors README | **Locked content; open polish** | `connectors/README.md` |
| Landing page section (HTML) | **Locked structure; open visual tuning** | `connectors/marketing/landing/connectors-section.html` |
| Launch blog post (1500 words) | Draft — needs your edit pass | `connectors/marketing/blog/launch-post.md` |
| Social drafts (X/LinkedIn/HN/WeChat/知乎) | Drafts — needs your voice + final length | `connectors/marketing/social/launch-thread.md` |
| Demo video scripts (6) | Storyboards complete — **need recording** | `connectors/marketing/videos/0[1-6]-*.md` |
| Montage script + voiceover | Draft | `connectors/marketing/videos/montage-voiceover.md` |
| Directory submission packages (5) | Pre-filled — needs your screenshot uploads | `connectors/submissions/*.md` |

## P1/P2 polish items from the design audit (deferred from launch-week)

From the product-designer review on 2026-05-22 (acted on the 3 P0s already):

| # | Where | What to fix |
|---|---|---|
| P1.4 | `connectors/README.md:3` | Lead with the one-line outcome ("Run a real RNA-seq, cryo-EM, or ADMET pipeline from Claude/Cursor/ChatGPT") before the tool name salad. Tool list moves to the second line. |
| P1.5 | everywhere | "30 seconds" claim appears 8+ times. Keep one canonical mention (landing terminal card). Strip from per-surface READMEs. |
| P1.6 | `connectors-section.html:139` | Change CTA from "See all six connectors →" to **"Connect Claude Code"** (or **"Open BioMate GPT →"** as secondary). |
| P1.7 | `connectors/wechat/README.md` | 7-line stub. Either delete or write a real surface page (Chinese-first). Landing card at `connectors-section.html:95` points here. |
| P1.10 | blog `:91` + README `:84` | "Free tier: 3 runs" claim conflict. Pick one or remove from blog. |
| P1.11 | landing | Add 7th card for Slack with "Pilot" pill + `mailto:hello@biomate.ai` CTA |
| P2.14 | everywhere | Boilerplate AI-sounding phrases — "real bioinformatics" appears in every H1; vary the language. |
| P2.15 | landing | Terminal card and H2 compete for the eye. Shrink terminal to ~70% width. |
| P2.17 | demo 4 script | Codex demo invents specific clinical findings. Either use real NA12878 sample + verify, or use `<top finding from your VCF>` placeholder. |
| P2.18 | claude-code README | Disconnect uses a curl with session cookie. Change to "visit biomate.ai/account/connectors and click Revoke." |

Full list with context: see the design review attached as commit `c72c7a1c9` description.

## Demos to record (this week)

6 demos × ~60–90s each + 60s montage. Scripts are at `connectors/marketing/videos/` — they include pre-roll checklists, beat-by-beat scripts, caption overlays, and editor notes.

| # | Demo | Length | Script |
|---|---|---|---|
| 1 | Claude Code × ADMET | 60s | `01-claude-code.md` |
| 2 | Claude Desktop × RNA-seq | 75s | `02-claude-desktop.md` |
| 3 | Cursor × CryoSPARC | 90s | `03-cursor.md` |
| 4 | Codex × Sarek WGS | 75s | `04-codex.md` |
| 5 | ChatGPT × IND §2.6.1 narrative | 90s | `05-chatgpt.md` |
| 6 | Open Claw / WeChat × ADMET (Mandarin) | 60s | `06-open-claw.md` |
| 7 | Launch montage | 60s | `montage-voiceover.md` |

### Recording stack (from the script's "Recording stack" section)

- macOS screen recording, 2560×1440
- iMovie for cuts + captions
- Hardcode key callouts (workflow ID, runtime, cost) as text overlays
- Music: 95–110 bpm "research montage" feel, NOT corporate stock

### Output formats per asset

| Format | Use |
|---|---|
| 16:9 @ 2560×1440 (60s montage) | YouTube, biomate.ai/connectors landing hero |
| 9:16 @ 1080×1920 (30s cut) | X/Twitter, LinkedIn vertical, WeChat 视频号 |
| 1:1 @ 1080×1080 (30s cut) | Instagram, LinkedIn feed |

## Screenshots needed for directory submissions

For each submission package at `connectors/submissions/*.md`:

| Submission | Screenshots needed |
|---|---|
| Cursor MCP directory | `screenshots/cursor-{rnaseq-stream,admet-qc-gate,cryosparc-result}.png` (paths referenced in `cursor-mcp-directory.md`) |
| ChatGPT GPT store | Cover image 2048×1024; one tool-result example |
| Anthropic MCP servers | Logo + a transcript screenshot |
| Anthropic Skills gallery | Skill bundle preview (rendered from `skills/biomate/`) |
| Slack App Directory | App icon 512×512 + demo workspace screenshot |

Logos / cover graphics — confirm with brand whether existing biomate.ai assets work or if new ones need to be commissioned.

## Brand voice consistency check

The design audit flagged repeated phrases across 8 surfaces. **One-pass cleanup** — replace these clichés:

| Cliché | Used in | Replace with |
|---|---|---|
| "real bioinformatics" | every H1 | concrete: "RNA-seq differential expression", "CryoSPARC refinement" |
| "from anywhere you already work" | landing + blog + LinkedIn | concrete surface name |
| "execution engine" | blog x3, README x2 | "BioMate runs the pipeline" |
| "30 seconds" | 8+ places | keep in landing terminal card only |
| "AI can write code. BioMate runs it." | montage + blog + thread | keep — it's the one strong line |

## Audit gaps that affect marketing claims

The viz/report audit (commit `c72c7a1c9`) found backend gaps that mean some demo promises are currently undeliverable. **Coordinate with backend before recording:**

- Demo 2 (RNA-seq) promises "top 20 DE genes when done" — backend has no `get_findings_table` primitive; comes back as free prose. **Either change the demo or wait for backend.**
- Slack README claims "posts final methods report as PDF attachment" — `files.upload_v2` bridge not built. **Either rewrite the README or wait for backend.**
- Demo 6 (Open Claw) shows thumbnails — currently dropped. **Either change the demo to text-only or wait for the thumbnail-forward fix.**
- Demo 4 (Codex) shows ASCII plots — Codex has no image rendering. **Wait for server-side ASCII renderer.**

Confirm with the backend team's `docs/20260526_TEAM_BACKEND_DEVOPS.md` what lands by recording day.

## Launch week schedule (your hand-off from launch coordinator)

Per `connectors/submissions/README.md`:

| Day | Submission | Owner |
|---|---|---|
| Mon | Anthropic MCP servers PR + Cursor MCP directory | designer + engineering for PR |
| Tue | Anthropic Skills gallery + OpenAI GPT store | designer |
| Wed | WeChat 公众号 + 知乎 announcement | marketer (Chinese-fluent) |
| Thu | HN Show HN + X thread + LinkedIn | marketer |
| Fri | Slack App Directory (deferred until pilot wraps) | — |

## Reference

- `docs/20260525_SESSION_SUMMARY.md` — full work index
- `docs/20260513_CONNECTOR_ARCHITECTURE_V2.md` — design rationale (useful for "why" questions in social engagement)
- Audit review (in commit `c72c7a1c9`) — the full P0/P1/P2 list with rationale
