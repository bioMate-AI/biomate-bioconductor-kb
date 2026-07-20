# Connecting BioMate to Instruments & the Wet Lab — Corrected: What's Built vs the Real Gap

**Date:** 2026-07-12
**Question:** "LLM is out of date, world models / physical AI is next. I want to connect our platform to instruments and the wet lab — how do we do this quickly?"

> **CORRECTION (after auditing `/Users/kky/biomate-connector`):** the "fast path" originally drafted below (watch-folder ingestion, Opentrons connector, SiLA2) is **already built.** This doc has been corrected to inventory what exists and pinpoint the actual gap: the loop is **reactive and one-way**, not a closed, agent-actuated DBTL loop. The staged plan at the bottom is superseded by the "Real Gap" section.

---

## Already built (audited 2026-07-12)

- **10 lab-instrument connectors** in `/Users/kky/biomate-connector/lab_instruments/`: Illumina BaseSpace, Nanopore MinKNOW, CryoEM EPU (`.mrc/.eer`), LC-MS (`.raw/.d/.wiff`), flow cytometer (`.fcs`), qPCR (`.eds/.pcrd`), plate reader (`.xlsx`), **Opentrons OT-2/Flex** (HTTP API: `health_check/upload_protocol/start_run/get_run_status/get_run_outputs`), Benchling ELN, and a **generic SiLA 2 gRPC adapter** (Hamilton STAR, Tecan Fluent, Sartorius, Cytena; port 50051).
- **`instrument_watcher.py`** — file-watcher daemon: `INSTRUMENT_TRIGGERS` (ext → workflow ID), configurable poll interval, posts to `/api/sessions`. (This *is* "Stage 0".)
- **19-tool MCP surface** (`biomate_mcp_server.py` / `tools_manifest.py`): `biomate_session`, `search_workflow`, `run_workflow`, `get_run`, `preview_file`, `export_report`, `analyze_results`, `query_database`, `resolve_accession`, `fetch_public_data`, `recall_memory`, etc. — but note: **all 19 are dry-lab** (search/run/preview/analyze).
- All AI surfaces (Claude/Cursor/Codex/ChatGPT) + messaging bots (Slack/Feishu/Telegram/WeChat) + OAuth 2.1/PKCE + keychain installer.

## The real gap: the loop is reactive and one-way

What exists is **instrument → data → analysis** (a sensor feeding the dry lab). What "physical AI / self-driving lab" requires is the **closed DBTL loop**: agent **designs → generates protocol → actuates → monitors → ingests → decides → actuates again.** The specific missing pieces:

1. **The agent↔instrument edge is not in the MCP surface.** The 19 MCP tools are all dry-lab; the lab-instrument connectors run as *separate daemons* that post to `/api/sessions`. The orchestration brain (`biomate_session`) **cannot directly command an instrument.** → Add actuation tools to the manifest (`run_instrument_protocol`, `get_instrument_status`, `list_instruments`) gated by **confirm-before-actuate**.
2. **Opentrons/SiLA2 are effectively read-only in the loop.** Opentrons is status-polling + uploading *pre-written* protocols; there is no **protocol generation** (natural-language/param → runnable protocol) wired into the agent. → Promote `upload_protocol()`+`start_run()` into an agent-callable, guarded action; add template/LLM protocol generation.
3. **No stateful lab-automation orchestration.** Explicitly not built: "run robot → wait 2 h → trigger assay → analyze → branch." → Build a **DBTL loop controller** — and reuse the existing **QC-gate + PROCEED/REFINE/PIVOT** machinery as its decision layer (PIVOT = physical failure / redesign).
4. **No physical error recovery or telemetry.** Only file-completion triggers; no rerun-on-clog, no live sensor feeds. → Add error-recovery hooks to the watcher and route physical failures into the PIVOT branch.
5. **Benchling is one-way** (posts data, doesn't pull ELN state back). → Two-way sync so the loop has provenance/state.

## Why this is close, not greenfield

Both halves exist: the **brain** (MCP orchestration + `biomate_session` + QC/PIVOT loop) and the **hands** (10 connectors incl. Opentrons + SiLA2). Closing the loop is a **state-machine + tool-exposure integration** on top of existing pieces — the agent↔instrument edge, protocol generation, and the DBTL controller — not a new hardware-integration project. That is an unusually strong position: most "physical AI" efforts have hands and no brain; BioMate has both and just hasn't wired them into a loop.

## Recommended next move (given what's built)

**Wire the agent↔instrument edge + a minimal DBTL loop on Opentrons.** Concretely: (a) add 3 actuation tools to the MCP manifest with confirm-before-run; (b) add protocol generation for one immune sample-prep protocol; (c) stand up the DBTL controller reusing QC/PROCEED-REFINE-PIVOT for one loop iteration on a gold-standard immune task (PBMC plating/stimulation → ingest → analyze → propose next). That single closed iteration is the "physical AI" milestone — and it's weeks, because the connectors and brain already exist.

---

## IMPLEMENTED 2026-07-12 — agent↔instrument edge (Opentrons)

Wired the missing agent↔instrument edge into the MCP surface. Changes in `/Users/kky/biomate-connector`:

- **`mcp/tools_manifest.py`** — new `instrument` tier + `local_only` flag on `ToolSchema`; three tools added: `list_instruments` (read-only), `get_instrument_status` (read-only), `run_instrument_protocol` (destructive_hint=true). All `local_only=true`, so they are excluded from the cloud surfaces (`to_openai`/ChatGPT, `to_anthropic`/Open Claw, OpenAPI, Skill catalog) and exposed **only over local MCP** (Desktop/Cursor/Codex) — correct, because the cloud backend cannot reach a robot on the lab LAN.
- **`mcp/biomate_mcp_server.py`** — `dispatch_instrument_tool()` + lazy `_load_opentrons()`; dispatches locally to the existing `OpenTronsConnector` (no cloud proxy). Hooked at the top of `dispatch_tool()`.
- **Guardrail:** `run_instrument_protocol` defaults to `confirm=false` → **pure offline dry-run** (compiles/returns the protocol, actuates nothing, needs no hardware). `confirm=true` verifies reachability (`health_check`) then `upload_protocol`+`start_run`. Marked `destructiveHint` so hosts also prompt.
- **Protocol generation:** accepts raw `protocol_code` OR a structured `transfers` spec, compiled via the connector's existing `generate_plate_transfer_protocol`.

**Validation (no robot needed):** both files `py_compile` clean; manifest regenerated (19→**22 tools**); verified instrument tools present in `to_mcp()` and **absent** from `to_openai()`/`to_anthropic()`/`openapi.json`; dry-run of a structured PBMC-transfer spec returned a valid compiled OT-2 protocol with `actuated=NO`.

**Regen note:** `python3 mcp/tools_manifest.py` also surfaced **pre-existing drift** in `connectors/chatgpt/openapi.json` (stale `s3_key`/`query_database` descriptions) unrelated to this change — now synced.

### DBTL controller — IMPLEMENTED (sim-validated) 2026-07-12

`lab_instruments/dbtl_controller.py` — a stateful **Design → Build → Test → Learn**
loop, dependency-injected so it runs and is testable without hardware or cloud:

- `DBTLController.run(params)` iterates DESIGN → BUILD/TEST → LEARN → DECIDE; REFINE loops, PROCEED/PIVOT stop.
- Injected fns: `design(params)→protocol`, `analyze(outputs,params)→{metric}`, `policy(metric,params,history)→(Decision,next_params,note)`. `Decision ∈ {PROCEED, REFINE, PIVOT}` — reuses the QC/PROCEED-REFINE-PIVOT contract.
- **Guardrail preserved:** BUILD/TEST only actuates when a real `robot` is attached AND `confirm=True`; otherwise it's a dry-run returning the compiled protocol.
- Real wiring helpers: `make_opentrons_design(...)` (uses the connector's real `generate_plate_transfer_protocol`), `make_biomate_analyze(client, goal)` (calls `biomate_session`), `threshold_policy(...)`.
- **Validated:** `run_sim_demo()` — a simulated PBMC cytokine-stimulation titration (saturating dose-response) converged REFINE→PROCEED to the target in 5 iterations; a separate stalled-response test drove REFINE→REFINE→**PIVOT**. All three branches reachable. DESIGN emits a real OpenTrons protocol each round; only actuation + analysis are simulated.

### Test results (2026-07-12, venv pytest)
- `tests/test_tools_manifest.py` — updated 4 tests to the new invariant (cloud tools on cloud surfaces; `local_only` tools MCP-only) + added `test_local_only_tools_in_mcp_but_not_cloud`. **31 passed.**
- `tests/test_instrument_dispatch.py` (new) — guardrail (dry-run never actuates), confirm→actuate order, error paths, `list_instruments` empty, DBTL PROCEED + PIVOT. **9 passed.**
- Full relevant suite (`test_tools_manifest` + `test_lab_instruments_e2e` + `test_mcp_e2e` + `test_instrument_dispatch`): **107 passed, 12 skipped (live/hardware), 0 failed.**
- **Bugs the tests caught:** (a) 4 manifest tests assumed "every tool in every surface" — corrected; (b) real import bug in `dbtl_controller.py` (bare `from opentrons_connector import` failed on package import) — fixed with try/except fallback.

### Remaining to productionize
1. **Real-robot validation** — `list_instruments` → `run_instrument_protocol(confirm=true)` against an actual OT-2/Flex; confirm `get_instrument_status` polling to terminal, then wire `DBTLController(robot=OpenTronsConnector(ip), confirm=True)`.
2. **Wire real LEARN** — replace sim analyze with `make_biomate_analyze` against the gold-standard immune assay (deconvolution vs flow / perturbation), ingesting via `instrument_watcher`.
3. **Physical error recovery + two-way Benchling sync** (per gap list above).
4. **Run the connector drift test** (`tests/test_tools_manifest_drift.py`) in the repo's own env and commit the regenerated artifacts (note the pre-existing openapi.json drift now synced).

---

## SUPERSEDED — original staged plan (kept for reference; Stages 0–1 already built)

---

## The strategic reframe (why this is not a pivot away from LLM)

"LLM is out of date" is half-hype. The real frontier architecture is a **stack**, not a replacement:

```
  Reasoning / orchestration brain   ← LLM agent (BioMate already IS this)
  Predictive world model            ← virtual-cell / perturbation simulators (as TOOLS)
  Physical actuation                ← instruments & robots (the missing "hands")
  Closed loop                       ← design → build → test → learn (DBTL)
```

- The **LLM is the durable orchestration layer**; world models and physical actuators are **swappable tools underneath it**. You don't drop the LLM — you extend the orchestrator you already have to (a) call world models and (b) actuate instruments.
- **BioMate is already the brain.** Connecting instruments = adding *hands* to a brain that exists. That is the fastest position anyone in this space can be in — most "physical AI" startups have hands and no brain.
- **The moat deepens.** Closed-loop execution data (design → wet-lab result → outcome) is even more proprietary than dry-lab traces. Owning the DBTL *loop* — not the model — is the defensible bet. This is the "self-driving immunology lab."

## The three edges of an agentic lab (and who owns them)

- **Agent↔tool edge** — **MCP** (Anthropic). BioMate already speaks this via its connectors. ✅ owned.
- **Agent↔agent edge** — **A2A** (Google). For multi-robot / multi-agent orchestration.
- **Agent↔instrument edge** — the still-unstandardized one. Emerging protocols: **LAP** (agent-to-instrument, arXiv 2606.03755); **SiLA 2** for deterministic instrument control. Broad vendor adoption is **2027–2028** — so build opportunistically on the best open APIs *now*, don't wait for the standard.

---

## Fast path — staged, fastest first

### Stage 0 — Watch-folder ingestion (days, uses what's already shipped)
Every instrument writes **output files** (FCS from flow/CyTOF, FASTQ from sequencers, MRC from cryo-EM, CSV/plate-reader, images). The BioMate **desktop app already has native file access**. Add a **watched-directory** ingestor: instrument writes → BioMate auto-detects file type → routes to the right workflow → results in the panel.
- **Why first:** zero vendor integration; works with *any* instrument; ships on the desktop app that exists.
- **Immune use case:** flow/CyTOF `.fcs` → auto-route to immunophenotyping; sequencer FASTQ → RNA-seq/deconvolution chain.

### Stage 1 — Actuation via Opentrons MCP (weeks, the fastest "physical AI" win)
Opentrons **OT-2 / Flex** liquid handlers expose an **HTTP API on port 31950**, an **official Opentrons MCP server**, and **OpentronsAI** (natural-language → protocol). Wrap the Opentrons MCP server as a BioMate connector → the agent can **run liquid-handling protocols from natural language**, not just analyze.
- **Why:** best open, battle-tested robot API; MCP is the edge BioMate already speaks; days-to-demo. (Note: HighRes × Opentrons announced agent-to-agent lab automation in 2026 — the ecosystem is moving here.)
- **Immune use case:** automated PBMC plating, cytokine stimulation, sample prep feeding the deconvolution / perturbation showcases → real DBTL loop on our own gold-standard tasks.

### Stage 2 — Cloud-lab backend (weeks–months, wet lab with zero capex)
**Emerald Cloud Lab / Strateos**-style programmatic labs let BioMate **design an experiment → submit via API → get data back → analyze → propose next**, with no hardware ownership. This is the fastest way to close a *real* wet-lab DBTL loop without building a lab.
- **Why:** removes the biggest blocker (owning/operating instruments); API-native, so it fits the orchestrator directly.

### Stage 3 — Standards-based instrument coverage (as vendors catch up)
Wrap **SiLA 2** drivers (plate readers, flow cytometers, liquid handlers; e.g. the open `ot2-controller` SiLA2 driver) as **MCP servers** — SiLA2 for deterministic control (muscles), MCP for the agent edge (nerves). Broad vendor coverage lives here but arrives 2027–2028; build per-instrument as specific customers need it.

---

## Recommended immediate move

**Stage 0 + Stage 1 in parallel.** Watch-folder ingestion makes *every existing instrument* a data source in days; the Opentrons MCP connector gives a genuine actuation demo in weeks. Together they produce the first **closed-loop artifact**: natural-language experiment → robot executes → data ingested → BioMate analyzes → proposes next step — on an immune sample-prep task tied to the gold-standard showcases. That demo *is* the "physical AI" story, built on the orchestration brain you already have.

## Honest frictions
- **Instrument heterogeneity** is the real cost — every vendor SDK differs; that's exactly why file-level (Stage 0) + best-open-API (Opentrons) + API-native cloud labs (Stage 2) are the fast wedges, and general SiLA2 is the slow-but-broad path.
- **Wet-lab reliability ≠ software reliability** — physical failures (clogs, contamination, plate errors) need a verification/QC loop; reuse BioMate's existing QC-gate + PROCEED/REFINE/PIVOT machinery for the physical loop.
- **Safety/authorization** — actuating real instruments needs guardrails (confirm-before-run on physical actions), analogous to the existing gated-execution pattern.

## Sources
- Self-driving labs 2026 — what works vs hype: https://qpillars.com/blog/self-driving-labs-2026-what-works-vs-hype
- HighRes × Opentrons agent-to-agent lab automation: https://clpmag.com/lab-essentials/lab-automation/highres-opentrons-ai-lab-automation-partnership/
- Opentrons MCP / lab-automation skill: https://mcpmarket.com/tools/skills/opentrons-lab-automation-1777683764614 · https://worldwide-studios.org/blog/physical-mcps-with-opentrons
- SiLA 2 standard: https://sila-standard.com/ · OT-2 SiLA2 controller: https://github.com/FlorianBauer/ot2-controller
- LAP — agent-to-instrument protocol: https://arxiv.org/html/2606.03755v1
