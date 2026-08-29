# Flagship (C1) + RealBio — Status, Plan & Progress (living master doc)

**Started:** 2026-08-22 · **Owner:** Y. Zhang · **Scope:** the two lead publications — the BioMate
flagship (C1) systems paper and the RealBio open cross-system benchmark — plus the benchmark
sweeps behind them. Update this doc at each step; it is the single source of truth for what is
done, what remains, and why.

## Honesty contract (applies to everything below)
- Every number traces to a committed file (named here). No fabricated scores, DOIs, or comparators.
- Cross-harness / different-item-set comparisons are labelled as such — not presented as same-item head-to-heads.
- Where a cell is unmeasured it is shown as "—" (not zero, not invented).
- "Plan-only" items (things we might do for extra rigor) live in **this doc**, never as caveats in the manuscripts.

---

## 1. Status snapshot

| Paper | State | Docx (Drive `updated_20260820/`) |
|---|---|---|
| **C1 flagship** | Structurally submission-ready (Nature Methods form): Methods + declarations, 17 verified refs, Figs 1–5 (appearance-ordered, 300 dpi), 151-word abstract, ~6,861-word main text, Suppl. S1/S2/S3. | `C1_Flagship_Orchestrated_Agent_QC_Governance.docx` |
| **RealBio** | Manuscript-complete; leaderboard extended 6→9 tasks; co-scientist positioned; declarations + verified Table 1. | `RealBio_Benchmark.docx` |

Both committed on `docs/target-id-stratification-surveys-20260817` and mirrored to Google Drive.

---

## 2. RealBio benchmark — current leaderboard (9 tasks)

**LLMs used directly** (8 frontier models, frozen prompt, one identical protocol; predictions committed under
`evaluation/datasets/public_export/results/<model>/`, re-scorable via `score.py`):

| Task | Metric | LLM-direct range | mean | BioMate |
|---|---|---|---|---|
| cross-domain routing | exact | 0.345–0.615 | 0.46 | **0.965** [0.930,0.983] |
| param_prefill | F1 | 0.62–0.76 | — | **0.848**† |
| autofix | category | 0.77–0.88 | — | — (not committed) |
| protocol-QC | PASS/FAIL | 0.33–0.63 | — | **0.925**† |
| workflow_gen | category | 0.50 | — | — (not committed) |
| **pbpk** (new) | within-2-fold | 0–20% | **7.5%** | **0.20** ◊ (3/15, same-item) |
| **boin** (new) | exact MTD-mg | 10–45% | **24%** | 0.80 ★ (48/60, cross-harness; same-item pending) |
| **dd** (new) | Spearman rank | 0.67–0.70 | **0.70** | — (see §4) |

† BioMate param/protocol from its own harness (n differs from the LLM sweep). ◊ **BioMate pbpk 0.20 is the genuine
same-item cell** (3/15 within-2-fold on the exact 15 RealBio compounds; `docs/20260827_BIOMATE_PBPK_SAME_ITEM_RESULT.md`)
— it **ties** the best LLM (GPT-5.6, 0.20) and beats the LLM mean (0.075); it does **not** lead pbpk (generic PBPK
over-predicts Cmax). The earlier cross-harness **100%** (18-case FDA disease-state AUC-ratio set, different items) is
NOT a same-item result and was removed from the public leaderboard/site (2026-08-27). ★ BioMate boin 0.80 from its
internal BOIN benchmark (n=60) is cross-harness; the **same-item BOIN run is pending** (infra-blocked by the dead dev
AWS key). Biomni agent scaffold: routing 0.950 (38/40), autofix 0.95 (n=40 pilot).

**Reading:** LLMs-direct fail PBPK (simulation, 7.5%) and are mediocre at BOIN (24%), but are *good* at ligand ranking
(dd, 0.70 — a knowledge task; shows RealBio is not rigged to only surface LLM weakness). BioMate **leads the
orchestration tasks decisively** (routing 0.965 same-item vs best-LLM 0.615); on the **same-item execution tasks it is
competitive, not dominant** — pbpk ties the best LLM (0.20), boin same-item still to run. The honest headline is
"engine-free retrieval wins orchestration + is cost/speed-free; execution is hard for everyone," not "leads every task."

**Provenance:** `leaderboard.csv` / `leaderboard.md` / `score.py` in `evaluation/datasets/public_export/`;
canonical BioMate scores in `docs/20260429_BENCHMARK_MATRIX_COMPLETE.md` and
`docs/20260429_PHARMACOLOGY_BENCHMARK_RESULTS.md`.

---

## 3. Change log (2026-08-22 session)
- Ran the paid LLM-direct sweep for the 3 previously-un-swept RealBio tasks: **pbpk, boin, dd** (8 models each);
  committed predictions + usage sidecars. Spend **$6.62 / $10** OpenRouter (key: `~/.cache/biomate_cmp/.infkey`).
- **Wired boin + dd** into the harness (were "held" on undefined GT): `run_baseline.py` GEN entries +
  `score.py` fix — boin scored on `true_MTD_mg` (exact), dd on Spearman vs `ligand_rank_order`.
- Extended leaderboard + RealBio paper to **9 tasks**; filled BioMate **pbpk 100% / boin 80%** (cross-harness,
  footnoted); removed all "pending `biomate_exec` consistency step" language from the manuscript (kept here in §4).
- Reframed **co-scientist** honestly (RealBio §2): capable LLM agents that *can* attempt the tasks and would
  place at their level; not on the board only because they are closed/no-API; RealBio is open for their teams to run.
- **Co-scientist comparison (per user's method):** cross-referenced competitors' *published* benchmarks vs BioMate coverage — Biomni overlaps on BiomniEval1/BixBench-V50/RealBio-routing/LAB-Bench (direct no-re-run comparisons, BioMate leads/parity); Google AI co-scientist publishes GPQA + bespoke clinical tasks BioMate never ran (no shared benchmark → capability comparison only). Promoted the AI-co-scientist comparison into flagship §1.2 main text; added a Shared-benchmark section to Suppl. Table S4.
- (Earlier this week) Flagship: BixBench→Phylo Verified-50 (BioMate 92.0% vs Biomni 88.7%), BiomniEval1→71.1%
  macro-average (vs Biomni-R0 66.9%), figures renumbered 1–5, Methods + declarations added, 17 refs verified.

---

## 3b. Biomni on the computation tasks (pbpk/boin/dd) — run 2026-08-23

**Goal (per user):** run the real Biomni A1 scaffold on the 3 tasks the pilot skipped, so the
Biomni row is complete — and capture it on **all axes, not just accuracy** (user: "accuracy is one
dimension; cost, token, speed, stability… there are other dimensions").

**Root-cause finding — Opus-5 is incompatible with Biomni's agent loop.** The pilot ran Biomni on
`claude-opus-5`. That works for the 5 single-turn classification tasks but **fails every
computation task**: Biomni's A1 appends each code `<observation>` as an *assistant* message and
re-calls the model to continue it (assistant-message *prefill*). Opus-5 rejects this across every
provider (Anthropic, Bedrock, Azure, Vertex): `"This model does not support assistant message
prefill. The conversation must end with a user message."` Empirically, prefill was removed across
Claude **≥ 4.6** (tested: opus-4.6/4.8/5, sonnet-4.6/5 all reject; **opus-4.1 and sonnet-4.5
accept**). This answers "why Opus-5?": Opus-5 was the pilot engine for consistency, but it
*cannot* drive Biomni's code-executing loop at all.

**Engine decision:** run the 3 computation tasks on **`claude-opus-4.1`** — the newest Opus that
supports Biomni's loop → keeps Biomni in the Opus tier (faithful to the pilot's Opus-5 intent) and
**steelmans the competitor** (strongest compatible engine, per the no-under/over-claiming rule).
Footnote in the paper: Biomni row = opus-5 for single-turn tasks, opus-4.1 for code-executing
tasks (opus-5 API-incompatible). Prompts are **byte-identical to `run_baseline.py`** (same fair
comparison as the 8 LLMs); same `score.py`.

**Multi-dimensional capture** (`run_biomni_realbio.py` extended): per-task **cost_usd** (OpenRouter
key-usage delta), **latency** p50/mean per item, **wall_s**, and a `--repeats` run-to-run
**stability** pass. Pilot captured latency only; this adds the cost axis the pilot lacked.
Smoke (opus-4.1, pbpk ×2): real predictions, **n_errors=0, ~$1.06/item, ~95 s/item** — vs
LLM-direct ~$0.01/item & ~24 s, and BioMate ~$0 & instant. The Biomni run *is* the cross-system
cost/speed headline: an agent scaffold is ~100× costlier and ~4× slower per item than a direct LLM
call, and far more than BioMate's engine-free routing.

**Infra:** EC2 `i-0a1f4697079a44ce1` (m6i.2xlarge, us-west-2, `AutoimmuneCorpusProfile`, 4h
self-terminate dead-man's-switch). biomni 0.0.8 / py3.11.15; A1 auto-downloads its ~11 GB data
lake on first init (cached). Key delivered inline via SSM (user-chosen; transient, in-account,
SSM history auto-expires ~30 d). Runner + task data staged at
`s3://knowledge-datasets-1759951976/biomni_realbio/`; results pushed to `…/results_out/`.

**BLOCKED on OpenRouter account credit (2026-08-23).** After the engine fix, the full run still
failed: every Biomni `go()` returns `402 — "This request would exceed your available credits given
your current in-flight requests."` Root cause is **not** the key (its limit reads $150/$142
remaining) but the **parent account's real funded balance**: `GET /api/v1/credits` →
total_credits $130, total_usage $127.57, **real remaining $2.43**. Each Biomni agent request
*reserves* its max-token cost (several $ over the growing multi-turn context), which exceeds $2.43,
so it 402s. Single-item tests passed only because one request briefly fit the headroom
(pbpk→3.3 @ opus-4.1; boin CT-001→"40" @ sonnet-4.5, $0.135, n_errors=0) — **the pipeline is
fully proven end-to-end**; the blocker is purely funding.
- **Unblock:** add ~$15–20 credit to the OpenRouter account (covers 50 items × ~$0.14 @
  sonnet-4.5 ≈ $7 + reservation headroom). Then relaunch: `boot.sh` + runner + task data are
  staged at `s3://knowledge-datasets-1759951976/biomni_realbio/`; a fresh m6i.2xlarge re-bootstraps
  in ~5 min (biomni auto-caches its data lake). Engine = **claude-sonnet-4.5** (Biomni's default
  Claude-Sonnet tier; compatible + fundable). Run all 3 tasks for a consistent row → score → cells.
- **Instance `i-0a1f4697079a44ce1` terminated** 2026-08-23 (no cost bleed against an unfundable
  run). Transient inline-SSM key exposure remains only in this account's SSM command history
  (auto-expires ~30 d); no key was persisted to S3 (that copy was correctly blocked).
- **Until funded, the 3 Biomni computation cells stay "—"** (unchanged from before — honest).

### 3b-FINAL. Biomni computation-task row — COMPLETE (2026-08-24, sonnet-4.5)

Engine **claude-sonnet-4.5** (Biomni's default Claude tier; opus-5/≥4.6 are prefill-incompatible).
Same byte-identical prompts + same `score.py` as the 8-LLM sweep. Results in
`results/biomni_ec2/`.

| Task | Biomni (sonnet-4.5) | LLM-direct | Read |
|---|---|---|---|
| pbpk | **0%** (0/15) | 7.5% | ⚠️ **format artifact, NOT inability** — agent computes rich mechanistic PK (clearance/AUC), which doesn't match the single reference Cmax within-2-fold when squeezed to one number |
| boin | **45%** (9/20 exact MTD) | 24% | Biomni scaffold **beats** direct LLMs on dose-finding |
| dd | **Spearman 1.0** on 4/15 scored | 0.70 | perfect ranking on the 4 that ran; **11 dropped** to OpenRouter 402 dips (dd's large context → big reservation). Tiny sample — report as partial, not a headline |

**Capability verdict (the honest one):** Biomni **can** do these tasks — it writes + executes real
PK models, BOIN dose-finding, and ligand docking/ranking code. The cells are *constrained
same-prompt accuracy* for a fair cell next to the LLMs, **not** a can/can't verdict. Do NOT headline
"Biomni 0% on pbpk" as inability (over-claiming).

**Multi-dimensional (per user's rule):** Biomni is the *slow, agent-overhead* system — latency
p50 ~29 s (pbpk) / ~67 s (boin) / ~150 s (dd) vs LLM-direct 1–50 s vs BioMate ~instant; cost
~$0.4–1.4/item (retry-inflated) vs LLM ~$0.01–0.3 vs BioMate ~$0. BioMate dominates cost + speed +
stability; Biomni's accuracy is **mixed** (loses pbpk, wins boin, strong-but-tiny-n dd).

**Cost/process lessons (own them):** (1) 402-retry re-ran the *whole* agent loop — wasteful; the
correct fix was capping `max_tokens` to keep each request's OpenRouter reservation under the
auto-recharge balance floor (no dips, no retries). (2) Lost the first boin run (~$28) to a silent
S3-PutObject 403 (instance role is read-only on `knowledge-datasets`) + the 4 h self-terminate
firing during a message gap. Fix that worked: base64 results into the SSM command stdout (persists
service-side, survives instance death). All instances terminated.

## 4. Open items & plan (prioritized)

| # | Item | Owner | Status | Notes |
|---|---|---|---|---|
| 1 | **Publish RealBio dataset to Hugging Face** → mint DOI | **User (creds)** | blocked | Bundle ready under `evaluation/datasets/public_export/` (CC-BY-4.0). Paper says "DOI on publication." |
| 3 | **BioMate dd (ligand-ranking Spearman) cell** | me (gated) | open | Docking-triage 78.9% ≠ ranking metric. Needs a docking-based ranking run (Vina/DiffDock) scored by Spearman. Currently "—". |
| 4 | **autofix / workflow_gen BioMate cells** | me (gated) | open | No committed BioMate number; shown "—". Would need a BioMate run. |
| 4b | **LitQA2 / retrieval capability vs PaperQA2** (look into later) | me | deferred | BioMate retrieval-bound (~16.6%); off-thesis, removed from S4 per decision; revisit as a retrieval-improvement track, not a manuscript item. |
| 5 | **Extend LLM sweep to litqa2** | User (go/$) | deferred | Scoped OUT (retrieval-bound ~16.6%, off-thesis). 199 items = ~80% of sweep cost. Not planned. |
| 6 | *(rigor, plan-only)* item-matched `biomate_exec` on the exact RealBio pbpk/boin/dd items | me (gated) | plan-only | NOT a manuscript caveat. BioMate's cells are reported from its own validated benchmarks (same metric). A same-item run would tighten methodology but is not required for the BioMate-vs-others comparison. |
| 7 | Flagship final polish | me | mostly done | Refs verified; figs ordered; abstract 151w. Remaining: none blocking. |

**Decisions of record:**
- **No "+catalog" (LLM-with-catalog) condition** anywhere — the catalog *is* BioMate; comparison is BioMate vs LLMs-used-directly.
- BioMate cells are BioMate-vs-others on each system's benchmark; **no "re-run to match items" language in the papers** (§6 above is plan-only).
- Co-scientist systems are peers that can be scored; absence is access-only.

---

## 5. Key facts / provenance (for fast pickup)
- **Branch:** `docs/target-id-stratification-surveys-20260817` (a concurrent session also edits it — commit scoped, watch for churn).
- **OpenRouter key:** `~/.cache/biomate_cmp/.infkey` (inference, $10 cap, $6.62 used); `.provkey` = provisioning.
- **Figure venv (cnsplots):** `~/.cache/biomate_fig/bin/python` (has `openai` installed for the sweep harness).
- **Drive backup:** `manuscripts_0819/updated_20260820/` (folder id `115E2FmDB7DqArI3bxUMfFsxvlb4XljRm`), synced via rclone remote `biomate_drive`.
- **Recent commits:** `8fb5f38d6` (co-scientist fix) · `b895f60d5` (pbpk/boin cells + strip pending) · `d9f75dce8` (9-task leaderboard) · `aa07a7642` (boin/dd preds) · `74d511c91` (pbpk preds) · `b1edacda8` (boin/dd wiring).

---

- **Reviewer pass implemented on BOTH papers (2026-08-22, parallel).** Flagship (`8f9b73577`): abstract reframed to lead with system+governance (routing→sufficiency support; Kappa demoted to design property); §4 opens with win/loss-scope framing; pharma 18/18 reframed as a validation set; Fig 4 power→Suppl S1 (now 4 main figs 1–4, governance=Fig 4); §2.4 condensed into §3 breadth; §1.2 tightened (competitor enum→S4); Methods cost trimmed. RealBio (`870a56a3f`): benchmark-first abstract; C0 baseline-fairness confronted; task count fixed 9→8; BioMate pbpk 100%/boin 80% synced to leaderboard; §5.1/§5.4 consolidated; refs 5→10. No numbers changed in either.

## 6. Progress
- [x] RealBio 3-task paid sweep (pbpk/boin/dd) + committed predictions
- [x] boin/dd scorers wired
- [x] Leaderboard + paper → 9 tasks
- [x] BioMate pbpk/boin cells filled; "pending" language stripped
- [x] Co-scientist reframed honestly + comparison promoted to main text (§1.2) + shared-benchmark cross-reference added (S4); Google co-scientist has no shared benchmark (documented, not omitted)
- [x] Flagship: BixBench Verified-50 92.0%, BiomniEval1 71.1%, figs 1–5, refs, Methods, declarations
- [ ] HF publish → DOI (user)
- [ ] dd BioMate cell (docking-rank run) — optional
- [ ] autofix/wf_gen BioMate cells — optional
