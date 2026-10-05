# RealBio capability-demo video series — spec & honesty ledger

**Date:** 2026-10-05 · **Owner:** video session (branch `cursor/tutorial-live-recording-and-report-editing-4ea7`, worktree `/Users/kky/biomate-review`)
**Decision (user, 2026-10-05):** record a dedicated per-task advantage demo for each RealBio task — the task → BioMate doing it live → our score vs LLMs-direct. EN + ZH. Reuse existing footage where an episode already shows the task; build new for boin + the orchestration tasks.

## Honesty contract (overrides any "make it look better")
- **Real leaderboard numbers only** (source: `docs/20260822_FLAGSHIP_REALBIO_STATUS_AND_PLAN.md` §2, public `reference/claude_design/webpage_design_v2/realbio.html`). Never fabricate a score.
- **No head-to-head score where BioMate has no committed cell** (autofix, workflow_gen, dd). Those become capability demos (no "vs LLM" number) or wait for a real run.
- **Ties are ties:** pbpk — "matches the best frontier model," not "beats." The advantage there is cost/speed/reproducibility, stated as such.
- **boin 0.80 is cross-harness** (BioMate's own n=60 BOIN benchmark vs the RealBio LLM sweep; same-item run pending/infra-blocked). Frame as "on our clinical dose-escalation benchmark, 0.80 vs 0.24 LLM-direct" — do NOT imply same-item.
- **No method disclosure** (per memory): state WHAT (the score, the outcome) + light credibility; not the retrieval/harness recipe.
- **GTM/buyer-facing:** scrub internal tool-stack names; the score comparison IS the advantage.
- The always-true moat message, even on ties: BioMate's orchestration answers are engine-free retrieval → ~zero per-query cost, instant, reproducible; LLM-direct pays per query, varies run-to-run.

## Per-task ledger (what each video may honestly claim)

| # | Task | BioMate | LLM-direct | Claim tier | Existing footage to reuse |
|---|---|---|---|---|---|
| 1 | **cross-domain routing** | **0.965** [.930,.983] | 0.46 mean (best 0.615) | **Lead (big)** | t0/m1/flagship routing moments |
| 2 | **param_prefill** | **0.848** F1 | 0.62–0.76 | **Lead** | flagship param strip; t1 |
| 3 | **protocol-QC** | **0.925** PASS/FAIL | 0.33–0.63 | **Lead (big)** | flagship QC gate; d2 hERG GOLD halt |
| 4 | **boin** (MTD-mg) | **0.80** (n=60, cross-harness) | 0.24 | **Lead (caveat)** | none — NEW |
| 5 | **knowledge** (BiomniEval1) | **71.1%** | (peer parity; Biomni 88.7→92.0 phylo set differs) | **Solid cell** | m1 search & evidence |
| 6 | **pbpk** (within-2-fold) | 0.20 (3/15 same-item) | 0.20 best, 0.075 mean | **Tie → cost/speed** | s2 PBPK |
| 7 | **autofix** | — (not committed) | 0.77–0.88 | **Capability only** | flagship auto-loop (Hero A) |
| 8 | **workflow_gen** | — (not committed) | 0.50 | **Capability only** | t1 / d1 design-&-generate |
| 9 | **dd** (ligand Spearman) | — (docking-triage 78.9% ≠ ranking) | 0.67–0.70 | **Capability only** | drug-dev / d1 / d2 |

**Build order (by strength + readiness):** 1 routing (pilot) → 3 protocol-QC → 2 param_prefill → 4 boin → 5 knowledge → 6 pbpk (tie framing) → then decide 7/8/9 (capability demos or run the cells).

## Video template (auto-play HTML contract, same pipeline as the tutorials)
~60–120 s, 3–4 scenes, `window.__timeline` / `__done` / `data-seconds`:
1. **The task** — what it is, why it's hard (one concrete example).
2. **BioMate doing it** — live footage/asset of BioMate performing the task.
3. **The result** — BioMate score vs LLM-direct, as a clean bar/number (real figures above). For ties: the match + the cost/speed/reproducibility advantage.
4. **Takeaway** — one honest sentence.
Narration EN (Aria) + ZH (Xiaoxiao) +40%; record → mux → rclone to the marketing Drive folder. Files: `reference/claude_design/tutorials/rb-<task>-walkthrough.html` + `narration/rb-<task>.{en,zh}.md`.

## Open decision (flagged to user)
Tasks 7/8/9 (autofix, workflow_gen, dd) have **no committed BioMate score**. Options: (a) run the benchmark cell to get a real number (some infra-blocked — dd needs a Vina/DiffDock ranking run; autofix/workflow_gen need a BioMate run), (b) ship them as capability demos with no head-to-head number, or (c) defer. Not fabricating a number for them.

## m2 / qPCR live-asset status (2026-10-05) — ✅ LANDED (both)
Both the m2 (RNA-seq DE) and qPCR ΔΔCq assets were produced by **real live BioMate AWS-Batch runs** and saved to `reference/claude_design/tutorials/assets/live/_raw/`.

- **qPCR** (`normqpcr_delta_delta_cq_normalization`) — app run `ab456bff-…`, rc=0, ~143 s, 2 Batch tasks. No input file staged → the workflow's one-click **demo path** (NormqPCR bundled TaqMan example, 2^-ddCt). Assets: `qpcr_relative_expression_plot.{pdf,png}` (10-gene bar plot, audited non-blank), `qpcr_ddCq_multiple.csv` (98 genes, byte-exact), `qpcr_ddCq_single_paired.csv`. Outputs lived in the Batch **work dir** (this subworkflow has no `publishDir`), harvested directly from S3. NB the backend validates `qpcr_hkg`/`qpcr_control_label` as *required* even though the demo path ignores them — pass both to clear validation.
- **DE** (`nf-core/differentialabundance`) — app run `2aa0891e-…`, rc=0, ~212 s, DESeq2 on the staged **airway/GSE52778** matrix (12,763 genes × 8 samples, 4 untreated vs 4 dex). QC gate **PASS**: 34,371 tested, **1,242 significant** (padj<0.05, |FC|≥2). Top hit SPARCL1 (ENSG00000152583, padj 1.7e-116, LFC +4.6) + PER1 — textbook dex biology. Assets: `deseq_dex_vs_untreated_volcano.{pdf,png}`, `deseq_dex_vs_untreated_PCA.{pdf,png}` (PC1 39% var cleanly separates conditions), `deseq_results_top200.csv`, `deseq_qc_metrics.json`. This workflow *does* publish to the outdir (9 files registered on the run record).

### Root cause of the prior "blocked" saga (correction)
The earlier diagnosis (dev restart loop + bare-S3-key + run-execution code bugs) was **wrong**. The real blocker was narrow: the **deployed MCP server's own principal** failed the `/api/workflows/execute` billing-quota / galaxy-account gate, surfacing only as an opaque `400` because the MCP client (`biomate-connector/mcp/biomate_mcp_server.py`) swallows the response body in `_classify_exc`. The **product execute path** (fixture login → `/api/workflows/search` → `/api/workflows/execute`) works first try and is exactly what the UI uses. Both runs above launched and completed cleanly with no code change. The `biomate-review/backend/lib/mcp/` edits from the prior session were to the **deprecated legacy v1.0.0 MCP server** (commit `147065713`), never deployed — harmless but irrelevant; the live MCP source is the connector repo.

## Filed gaps
1. ~~**Dev backend restart loop (2026-10-05):**~~ **RETRACTED — this gap was a misdiagnosis.** Dev is stable; two Batch runs (143 s and 212 s) completed cleanly on 2026-10-05 ~20:13–20:20 UTC. See the root-cause correction above. The real issue was the deployed MCP principal's quota/account gate on `/execute`, not dev stability.
2. **MCP client swallows `/execute` error bodies:** `biomate-connector/mcp/biomate_mcp_server.py::_classify_exc` reduces a `400` to `UNKNOWN_ERROR` with no server message, which hid a plain `missing_required_params` / quota rejection for the entire prior session. It should surface `response.text`/JSON `error` so callers can act. (Deployed source = connector repo; the `biomate-review/backend/lib/mcp/` copy is the deprecated legacy server.)
3. **Deployed MCP tool descriptions are stale:** the live `search_workflow` tool still says "2,455 indexed workflows across 34 domains" — the connector's `tools_manifest.*` was not re-synced after the catalog-count fixes landed in `biomate-review`. Regenerate + redeploy remote-mcp from the connector repo.
4. **Output harvesting is inconsistent across workflows:** `nf-core/differentialabundance` publishes to the outdir and registers `output_files` on the run record; `normqpcr_delta_delta_cq_normalization` has no `publishDir`, so its outputs stay in the Batch work dir and `output_files`/`s3_output_files` come back `[]` on a successful run. The completion harvester should also sweep emitted process outputs for subworkflows lacking `publishDir`.
5. **GEO Data Connector (wf 10672) can't handle RNA-seq GEO series:** GEOquery series matrix carries no expression table for RNA-seq; it needs to fall back to supplementary raw-count files or route RNA-seq accessions to a counts source (recount3). Confirmed on GSE52778.

## Change log
- 2026-10-05 — series spec created; honesty ledger built from the RealBio leaderboard; routing pilot next.
- 2026-10-05 — m2/qPCR assets staged (DE via recount3/GSE52778 real counts); blocked on dev restart loop; two gaps filed.
- 2026-10-05 (later) — **both m2 + qPCR live assets LANDED** via real Batch runs (DESeq2 212 s, qPCR 143 s), saved to `assets/live/_raw/`, visually audited (volcano/PCA/bar plots all real & correct). Root cause of the prior "blocked" saga corrected: it was the deployed MCP principal's `/execute` quota gate (opaque 400), **not** dev instability or run-execution code. "Restart loop" gap retracted; 3 new real gaps filed (MCP error-swallowing, stale MCP tool descriptions, inconsistent output harvesting).
- 2026-10-05 (later still) — **m2 + qPCR tutorial VIDEOS rendered EN+ZH and uploaded.** Real DESeq2/qPCR outputs wired into the walkthrough HTML (`de-results.png` rendered from the real DE table via `scripts/recording/make_m2_results_table.py`; `de-volcano.png`, `qpcr-results.png` = real plots). Pipeline: edge-tts (Aria EN +40%, Xiaoxiao ZH +50%) → `record-walkthrough-{m2de,qpcr}.py` → `mux-walkthrough-*.py`. m2 scene slots 5/9 widened (28→31, 34→40 s) so both languages fit with no truncation (commit 1619abd0d). 4 mp4s (m2 EN 342 s / ZH 347 s, qPCR EN 268 s / ZH 266 s) audited frame-by-frame (real volcano + DE table + 2^-ddCt bar plot all render in-video) and uploaded to `biomate_drive:…/marketing/data_centroid_tutorial/videos/`.
