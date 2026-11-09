# User-Reported Issues — Manual Test Plan (verification checklist)

**Date:** 2026-11-09
**Target:** https://dev-public.biomate.ai (all fixes deployed; see commit column)
**Login:** E2E fixture `lifeifei163361@163.com` (password in `~/.config/biomate/e2e_fixture_password`), or any account.
**Scope:** every issue the user reported this session — the 30-screenshot UI backlog plus email, cold-start, LLM settings, the Models module, and PR hygiene.

How to use: run each case, fill the **Result** column (PASS / FAIL / N-A), attach a screenshot for any FAIL. Each case lists the fix commit so a regression can be bisected.

---

## A. Dataset & workflow panel (screenshot backlog)

| # | Issue (as reported) | Steps | Expected | Commit | Result |
|---|---|---|---|---|---|
| A1 | CSV dataset "cannot handle" / wrong stat grid | Open a project, upload a CSV (incl. a header-only CSV), open the dataset viewer | Stat grid reconciles with the parsed preview; no "—" placeholders; header-only CSV is readable (not blocked) | 3823ee6aa8 / backend 9228b39e73 | |
| A2 | QC wrong under 溯源 (lineage) | Open a CSV dataset → Lineage/溯源 tab | No false QC error from a profiling failure | 3823ee6aa8 | |
| A3 | "Needs attention" false amber | Upload a dataset that fails profiling | No false amber "needs attention" state | 3823ee6aa8 | |
| A4 | Workflow panel param strip too detailed | Send a workflow request, open the right panel | Input rows show basename only; Contrasts de-duplicated | 3823ee6aa8 | |
| A5 | File input shown optional when required | Open a workflow needing a data input (e.g. MG differential expression) | Missing required data inputs are flagged required; gate respects required-ness | 40c814f12e | |
| A6 | Confusing per-phase parameters | Open a multi-phase workflow, collapse a phase | "configured per phase — open the Phases tab" pointer; **params listed one `label: value` per row** (not a crammed run-on line) | 3823ee6aa8 / 9fcdea34ba | |
| A7 | Path parameter edit cramped | Edit a path/file param in the panel | Field is `flex-1 min-w-0`, not clipped | 3823ee6aa8 | |
| A8 | Skip-phase / new-step buttons shown without backend | Open any workflow | Skip-phase hidden unless skippable; no "chat for new step" button | 3823ee6aa8 | |
| A9 | Duplicate after-run kicker | Complete a run, view After Run | Single gated kicker, not duplicated | 3823ee6aa8 | |

## B. Select-dataset dialog & From-URL

| # | Issue | Steps | Expected | Commit | Result |
|---|---|---|---|---|---|
| B1 | No multi-select | Open "Select dataset" dialog | Multi-select works; footer shows "Use selected (N)" | 8b2d54798f | |
| B2 | Errored history items shown | Open the dialog with a history that has errored items | Errored items filtered out | 8b2d54798f | |
| B3 | Internal `GalaxyChat-*` history names | Open the dialog; look at history list | Shown as "Chat session · <date>" (not raw `GalaxyChat-2026-…`); searching "chat" still finds them | 9fcdea34ba | |
| B4 | From-URL tab a dense wall | Switch to the "From URL" tab | Input + Import at the **top**; examples/notes collapsed under "Examples & accepted sources" | 9fcdea34ba | |

## C. Chat & project

| # | Issue | Steps | Expected | Commit | Result |
|---|---|---|---|---|---|
| C1 | Raw dataset UUIDs / IDs in chat prose | Ask the assistant about an uploaded file ("summarize the counts matrix") | It refers to the file by **name** only; never prints id/UUID/s3_uri in prose | aebf2f5b4c | |
| C2 | Missing project-file context | Select a project file, ask a question about it | The assistant has the file context (doesn't ask you to re-upload) | 0a1b80b736 | |
| C3 | Unexpected workflow on attach-intent | Attach a file with a non-analysis message | No spurious workflow generation (attach-intent guard) | 0a1b80b736 | |
| C4 | "Open in Jupyter" fails | Open a dataset → Open in Jupyter | HDA readiness wait; friendly error if not ready (no raw ECONNREFUSED/IP) | 0a1b80b736 | |

## D. Cold-start examples (natural query text)

| # | Issue | Steps | Expected | Commit | Result |
|---|---|---|---|---|---|
| D1 | Examples read as demo scaffolding | New chat → Cold-start dashboard → expand "Data analysis" → "Try sample data" tab | Example labels are **natural queries** (e.g. "Find differentially expressed genes in myasthenia gravis vs healthy PBMCs"), not "Try sample data: …" | 7bff3c2e56 | |
| D2 | Hospital examples say "demo" | Same dashboard, hospital examples | "Integrate a multi-omics cohort … with SNF" / "Train a subtype classifier …" — no "Try hospital demo" | 7bff3c2e56 | |
| D3 | Internal examples reference "demo project" | Search module → "Internal" track | "Which datasets and sample groups does this project contain?" — no "prepared MG demo project" | 7bff3c2e56 | |
| D4 | Seeded prompt dumps demo/Project-ID text | Click any sample example | Composer fills a natural query; still attaches the sample files; brief honest note only ("synthetic sample data") — no "preserved fixture / no prior run implied / Project ID: …" | 7bff3c2e56 | |

## E. Settings — LLM

| # | Issue | Steps | Expected | Commit | Result |
|---|---|---|---|---|---|
| E1 | Default reveals the internal models | Settings → API/LLM → "BioMate Default" | Reads "Hybrid — automatically uses the best model for each task"; does **not** name Gemini/Claude | 50223caf0b | |
| E2 | Model list missing / too sparse | Settings → LLM → select **OpenRouter** provider | Grouped list: **Open-source** (glm-5.3-prime ★, deepseek-v4-pro, qwen3-235b-a22b-2507, kimi-k3, llama-4-maverick) and **Proprietary** (claude-opus-5.5, claude-sonnet-5.5, gpt-6.1-sol-pro, gemini-3.1-pro-preview, grok-4.7, mistral-large-4-0) | 868833ee82 | |
| E3 | List slugs don't resolve | Click a chip, save, send a chat | Model routes without a 404 (all 11 verified live on OpenRouter 2026-11-09) | 868833ee82 | |
| E4 | China origin should use best Chinese LLM | Send a chat with a `zh-CN` Accept-Language (or a `CN` geo header), managed default, no BYOK | Routes to `z-ai/glm-5.3-prime` (benchmark best Chinese model) | 50223caf0b | |

## F. Models module

| # | Issue | Steps | Expected | Commit | Result |
|---|---|---|---|---|---|
| F1 | Too few ML methods / diffusion | Models → method list | 9 methods incl. 3 diffusion (protein, scRNA, **tabular**) | 9228b39e73 | |
| F2 | Tabular diffusion setup | Models → select "Tabular diffusion" | Structured SpecSetup panel (framework, target column, rows-to-generate, …); not routed to chat-setup | 9228b39e73 | |
| F3 | Dead model-object buttons | Open a model object | No unwired action buttons shown | 50768d27a3 | |
| F4 | Instructions: Notes→Memory | Project → Instructions | Section labelled "Memory" (not "Notes"); seeded rules carry "may be project defaults/examples" hint | 683da003f2 / 9fcdea34ba | |

## G. Email notifications

| # | Issue | Steps | Expected | Commit | Result |
|---|---|---|---|---|---|
| G1 | No email on new registration | Register a NEW address (post-deploy) | "New BioMate registration" email arrives at xiaoni5122@gmail.com **and** yaoyun.zhang@biomate.ai | 7653d821bd + IAM SES grant | |
| G2 | Exceptions not emailed | Trigger a server 5xx | Throttled "Unhandled server error (5xx)" alert email — **PHI-safe** (error class/route pattern/ref only; no raw path/message/stack) | 1460f960b3 | |
| G3 | Delivery was fully broken | Check dev frontend logs on a send | `[EmailService] SES sent to …` (was failing silently; `galaxy-dev` now has `ses:SendEmail`) | IAM grant (SNSAndEventsAccess) | |

## H. Hygiene

| # | Issue | Steps | Expected | Commit | Result |
|---|---|---|---|---|---|
| H1 | PR #341 "has conflicts" | GitHub PR #341 | 0 behind base, MERGEABLE (remaining BLOCKED = required review + checks, not a conflict) | c46deee558 | |

---

## Known caveats (not yet verified end-to-end)
- **G1/G2** email delivery: fixed + SES granted, but **no registration has occurred since the fix** (the last 24h signups predate it), so the notification path is *not yet proven live* — run G1 with a fresh address to confirm.
- **E4** China routing only activates on the server-side OpenRouter path (needs `OPENROUTER_API_KEY` on the host) and when the user hasn't chosen their own model.
- This plan verifies at the **functional/code level**; a pixel-level visual diff of each state against the `localhost:7779` reference is a separate pass.
