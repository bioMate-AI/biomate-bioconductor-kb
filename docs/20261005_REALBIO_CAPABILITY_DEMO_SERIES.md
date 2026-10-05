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

## m2 / qPCR live-asset status (2026-10-05) — staged, blocked on dev infra
Both the m2 (RNA-seq DE) and qPCR ΔΔCq assets are **fully staged and server-accepted**, blocked only by a dev backend **restart loop**.
- **qPCR:** workflow_id **14339** (normqpcr_delta_delta_cq_normalization); Cq CSV in S3 (`users/fd5a73ac-…/12388981-…-cq_table.csv`); params `{input:<that>, qpcr_hkg:"GAPDH,ACTB", qpcr_control_label:"control"}`. Emits `ddCq_relative_expression.csv` (the fold-change table = qpcr-results) + a **bar** plot (not a volcano). 5 runs killed by infra restarts.
- **DE:** workflow_id **1497** (nf-core/differentialabundance). Real published raw counts via **recount3 SRP033351 = GSE52778** (NOT a FASTQ reprocessing): matrix 63,856 genes × 8 airway samples (Untreated SRR1039508/512/516/520; Dex SRR1039509/513/517/521), sanity-checked (CRISPLD2 strong dex induction). matrix/samplesheet/contrasts all in S3; params `{input:<ss>, samplesheet:<ss>, matrix:<mtx>, contrasts:<ctr>, study_type:"rnaseq"}`. Emits DESeq2 table + volcano (de-results, de-volcano). 2 runs killed by infra restarts.
- **To finish:** when dev is genuinely stable (a run survives >5 min), resubmit both (one `run_workflow` each) → get_run → download to `assets/live/_raw/`. Nothing to rebuild. Subagent `a54bfca796fee1071` holds the context (paused).

## Filed gaps
1. **Dev backend restart loop (2026-10-05):** Galaxy backend hosting the Nextflow head restarted ~every 3–5 min (observed 10:34/10:36/10:46/10:53/10:54/10:59 UTC); runs need 2–5 min so none survive. `/api/health` returns ok in the gaps between restarts (misleading). Not fixable from the MCP client / SSM read-only — needs whoever owns dev to stabilize it.
2. **GEO Data Connector (wf 10672) can't handle RNA-seq GEO series:** GEOquery series matrix carries no expression table for RNA-seq; it needs to fall back to supplementary raw-count files or route RNA-seq accessions to a counts source (recount3). Confirmed on GSE52778.

## Change log
- 2026-10-05 — series spec created; honesty ledger built from the RealBio leaderboard; routing pilot next.
- 2026-10-05 — m2/qPCR assets staged (DE via recount3/GSE52778 real counts); blocked on dev restart loop; two gaps filed.
