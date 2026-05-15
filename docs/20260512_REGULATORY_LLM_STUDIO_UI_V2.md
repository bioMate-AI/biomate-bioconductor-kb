# Regulatory LLM Studio UI — v2 Refinement for Claude Design

**Date:** 2026-05-12
**Supersedes:** `docs/20260504_REGULATORY_LLM_STUDIO_UI_REQUIREMENTS.md` (the v1 doc — its layout and Dataset/Pairs tabs are still valid; this doc *replaces* the Fine-Tune and Evaluate tabs and *adds* two new tabs)
**Audience:** Claude Design
**Stack:** React + TypeScript + Tailwind/shadcn (same as v1)

---

## Why a v2

Between v1 (2026-05-04) and now (2026-05-12), the pipeline architecture changed in three load-bearing ways. The UI must follow.

| What changed | v1 UI implication | v2 UI implication |
|---|---|---|
| Quality signal is no longer ROUGE-L — it's **9 deterministic checkers** from FDA reviewer checklist v2 (MRSD arithmetic, ICH structural compliance, phase-gating, etc.) | Eval tab shows ROUGE-L / BERTScore as primary metrics | Eval tab shows **per-checker pass rates** as primary metrics; ROUGE-L demoted to secondary signal |
| Training data is now **checker-grounded synthetic** (each example provably satisfies a verifier before being added to corpus) | Dataset tab assumes scraped/curated real prose | New **Task Generators** tab — manage the 5 generators (MRSD, skeleton, phase-gating, tabulated, adversity), each with its own checker pass rate |
| Pipeline is now **2-stage**: v6 SFT → v7 DPO via contrastive pairs | Fine-Tune tab was a single-step config | Pipeline view shows v6/v7 lineage; DPO pair curation is a new sub-surface |

The information density principle from v1 still applies: this is a developer-grade ML studio, not a consumer wizard.

---

## Updated information architecture

```
SIDE NAV (unchanged from v1)
├── Dataset           ← unchanged (real prose corpora)
├── Task Generators   ← NEW (5 synthetic task generators)
├── Training Pairs    ← unchanged (SFT pair review)
├── DPO Pairs         ← NEW (chosen/rejected pair review)
├── Fine-Tune         ← REPLACED (now pipeline-aware: SFT + DPO)
├── Evaluate          ← REPLACED (per-checker pass rates)
└── Deploy            ← unchanged
```

---

## NEW Tab: Task Generators

### Purpose

The v6 corpus is built from 5 **checker-first task generators**. Each generator produces synthetic SFT examples that are filtered through a deterministic checker before being added to the training pool. This tab is where the regulatory affairs scientist and ML engineer monitor, configure, and re-run generators.

### Layout

```
Task Generators                                            [+ New Generator]

┌────────────────────────────────────────────────────────────────────────┐
│ Generator              Checker        Examples  Pass%   Last Built     │
├────────────────────────────────────────────────────────────────────────┤
│ ● task5 MRSD comp      mrsd_verifier    500    100%    2026-05-10  ⚙   │
│ ● task6 skeleton       structural_v     1,288  100%    2026-05-10  ⚙   │
│ ● task7 phase-gating   phase_gating     300    100%    2026-05-11  ⚙   │
│ ● task8 tabulated      tab_summary      300    100%    2026-05-11  ⚙   │
│ ● task9 adversity      adversity_lang   300    100%    2026-05-11  ⚙   │
└────────────────────────────────────────────────────────────────────────┘

Total: 2,688 checker-grounded synthetic examples · all 100% pass
```

**Row click** expands an inline detail card with:

```
task5 MRSD computation                                                  ✕
─────────────────────────────────────────────────────────────────────────

Generator                              Checker
─────────                              ───────
File: scripts/generate_mrsd_sft_task.py    File: mrsd_verifier.py (C1)
Sampler space:                            Verifies:
  species ∈ {mouse, rat, dog, monkey,       1. Extract NOAEL + species + MRSD
              rabbit, minipig}              2. Recompute HED via FDA BSA factor
  NOAEL ∈ [0.5 – 2000 mg/kg]               3. Recompute MRSD = HED ÷ SF
  safety factor ∈ {10, 50, 100}            4. Pass if within 10% rel error
  Excluded: oncology (ICH S9 path)

Reject reasons (last run)                Coverage by species
  rounding edge cases:       19 (1%)       mouse:    83 examples
  none other                                rat:      85 examples
                                            dog:      89 examples
                                            monkey:   75 examples
                                            rabbit:   82 examples
                                            minipig:  86 examples

Sample example                              [Regenerate]  [Inspect All]
─────────────────────────────────────────────────────────────────────
USER  In a 28-day repeat-dose study targeting psoriasis, NOAELs:
      rabbit 0.5, mouse 1000, monkey 1000 mg/kg/day. Identify the
      most sensitive species, compute HED and MRSD…

ASST  Per FDA 2005 guidance, HED was derived for each species…
      The rabbit was identified as the most sensitive species
      with a NOAEL of 0.5 mg/kg/day, yielding an HED of 0.16 mg/kg
      (BSA factor 3.1). The MRSD of 0.016 mg/kg, calculated using
      a safety factor of 10, is proposed in accordance with ICH M3(R2).

CHECK ✓ HED arithmetic correct (computed 0.161, stated 0.16)
      ✓ MRSD arithmetic correct (computed 0.0161, stated 0.016)
      ✓ Species in BSA table
```

**Why this matters:** the regulatory affairs scientist needs to *see* what synthetic data looks like, *audit* sampler-space coverage (e.g., is the dog over-represented?), and *re-run* a generator with adjusted constraints. The checker pass rate is the headline metric per generator.

**"+ New Generator" button** opens a guided modal — described later under "Authoring a new task generator."

---

## NEW Tab: DPO Pairs

### Purpose

v7 trains on (prompt, chosen, rejected) pairs. There are two pair sources:
1. **Synthetic mutations** — chosen = checker-passing SFT example; rejected = same example with one element mutated to fail (wrong arithmetic, dropped subsection, etc.)
2. **Rejection sampling** — generate N completions from v6 at high temperature; partition by checker pass/fail; pair first-pass with first-fail

This tab shows both pools, allows filtering by task, and lets the user spot-check pairs to make sure the rejected variant is *meaningfully* worse (not just trivially different).

### Layout

```
DPO Pairs                              Task: [All ▾] Source: [All ▾]

Stats: 2,658 synthetic · 0 rejection-sampled (v6 training in progress)
       All pairs verified contrastive (chosen passes checker, rejected fails)

┌────┬─────────┬───────────────┬──────────────────────────────┬──────────┐
│ #  │ Task    │ Source        │ Chosen → Rejected (diff)     │ Status   │
├────┼─────────┼───────────────┼──────────────────────────────┼──────────┤
│ 1  │ MRSD    │ synthetic     │ HED 0.16 → 0.48 (mut 3×)     │ ✓ valid  │
│ 2  │ skeleton│ synthetic     │ dropped "Genotoxicity" head  │ ✓ valid  │
│ 3  │ phase   │ synthetic     │ removed Ames + hERG bullets  │ ✓ valid  │
│ 4  │ tabul.  │ synthetic     │ removed NOAEL column         │ ✓ valid  │
│ 5  │ advers. │ synthetic     │ "no findings" → "non-advers" │ ✓ valid  │
└────┴─────────┴───────────────┴──────────────────────────────┴──────────┘
```

**Row click** opens a **3-pane diff viewer**:

```
Pair #1 · MRSD computation · synthetic                                   ✕
─────────────────────────────────────────────────────────────────────────

PROMPT                                                  
  In a 28-day repeat-dose study targeting psoriasis, NOAELs:
  rabbit 0.5, mouse 1000, monkey 1000 mg/kg/day…

CHOSEN (passes checker)              REJECTED (fails checker)
─────────────────────────            ──────────────────────────
The rabbit was the most              The rabbit was the most
sensitive species (NOAEL              sensitive species (NOAEL
0.5 mg/kg/day). The HED of            0.5 mg/kg/day). The HED of
**0.16** mg/kg was calculated         **0.48** mg/kg was calculated
using BSA factor 3.1…                 using BSA factor 3.1…

CHECKER VERDICT
  Chosen:    ✓ MRSD passed (HED computed 0.16, stated 0.16)
  Rejected:  ✗ MRSD failed (HED stated 0.48, computed 0.16, err 200%)
```

**Why this matters:** DPO success depends on the rejected variant being *plausibly bad* — not random gibberish. The diff viewer lets the user verify that the mutation produced a realistic regulatory error.

**Top-bar actions:**
- `[Run Rejection Sampling]` — opens config (only enabled when v6 adapter exists; shows N samples per prompt, temperature, target pair count, estimated time)
- `[Export merged pool]` — emits `merged_pairs.jsonl` ready for `scripts/train_v7.sh`
- `[Discard pair]` per row — manual veto for synthetic mutations that don't make regulatory sense

---

## REPLACED Tab: Fine-Tune (v2)

### Purpose

The Fine-Tune tab now has to manage a **multi-stage pipeline**, not a single config. The visual frame is a horizontal stage diagram.

### Layout

```
Fine-Tune Pipeline                                           [+ New Run]

  ┌────────────┐    ┌────────────┐    ┌────────────┐    ┌──────────────┐
  │ Base Model │──▶ │  v6 SFT    │──▶ │ Eval + DPO │──▶ │   v7 DPO     │
  │ Qwen3-8B   │    │  (running) │    │   pairs    │    │              │
  └────────────┘    └────────────┘    └────────────┘    └──────────────┘

  ──────────────────────────────────────────────────────────────────────
  ACTIVE: v6 SFT (job b0x88j2b4)
  ──────────────────────────────────────────────────────────────────────

  Configuration                          Live metrics
  ─────────────                          ────────────────────────────────
  Adapter target:  v6                    Step: 367 / 1,107  (33%)
  Base model:      Qwen3-8B              Loss: 0.04  (train) / 0.06 (eval)
  LoRA rank/α:     16 / 32               Token acc: 98.5%
  Epochs:          3                     Entropy: 0.05
  LR:              2e-4                  ETA: ~6h 20m
  Grad accum:      16                    
  Data:            splits_v6/            ▁▃▅█▆▅▄▃▂▂▁▁▁▁▁▁▁▁  loss curve
                   5,892 train
                   326 dev / 326 test    [View Logs] [Stop]

  ──────────────────────────────────────────────────────────────────────
  COMPLETED RUNS
  ──────────────────────────────────────────────────────────────────────

  ✓ v4  (2026-05-08)   1,727 ex · ROUGE 0.576 · audit 92% · [Eval] [Deploy]
  ✓ v3  (2026-05-07)   1,370 ex · ROUGE 0.568 · audit 86% · [Eval] [Deploy]
  ✓ v2  (2026-05-06)   2,093 ex · ROUGE 0.282 · audit ―   · [Eval] [Deploy]
```

**Stage cards** at the top — clickable; each opens its sub-config. Stage status colors:
- gray = not started
- blue (spinner) = running
- green = complete
- red = failed
- amber = needs attention (e.g., DPO pairs not collected yet)

**Why the pipeline view:** v1's "single new job" form hides the relationship between v6 and v7. The pipeline frame makes it explicit that v7 *resumes from* v6, and that DPO pair collection is a step *between* them.

---

## REPLACED Tab: Evaluate (v2)

### Purpose

The headline metric for a regulatory LLM is no longer ROUGE-L or BERTScore. It's **per-checker pass rate**, because each checker maps to a specific FDA reviewer concern (MRSD arithmetic, ICH structural compliance, etc.). ROUGE-L is kept as a secondary signal.

### Layout

```
Evaluate                                              [Run Evaluation ▾]
──────────────────────────────────────────────────────────────────────

PRIMARY: v2 Checklist Pass Rates
                                  v4         v6           v7
                                  (current)  (training)   (planned)
──────────────────────────────────────────────────────────────────────
  A   Structural (ICH M4S(R2))    0%         ━━━ pending  ━━━
  A2  Tabulated (5 templates)     ―          ━━━ pending  ━━━
  B4  Adversity language          ―          ━━━ pending  ━━━
  C1  MRSD arithmetic             0%         ━━━ pending  ━━━
  C2  Phase-gating ICH M3(R2)     ―          ━━━ pending  ━━━
  D1  NOAEL §2.6.6 ↔ §2.6.7       ―          ━━━ pending  ━━━
  E1  Citation governs section    92%        ━━━ pending  ━━━
  E4  BM25 retrieval grounded     54%        ━━━ pending  ━━━
──────────────────────────────────────────────────────────────────────
  Composite (target ≥80% all)     2/8        ━━━          ━━━

SECONDARY METRICS (deprecated as primary, kept for comparison)
  ROUGE-L                         0.576      ―            ―
  BERTScore F1                    0.85       ―            ―
  citation_recall (substring)     13%        ―            ―   ← do not optimize

[Per-checker drill-down ▾]   [Per-task drill-down ▾]   [Export]
```

**Color coding the pass rate cells:**
- ≥80% → green text
- 50–79% → amber
- <50% → red
- `―` = not measured (gray)
- `━━━` = run pending (animated bars)

**Drill-down panes** when clicking a checker:

```
C1 MRSD arithmetic — drill-down
──────────────────────────────────────────────────────────────────────

Pass:  v4: 0/12 (0%) grounded · 0 passed
       v6: pending

GROUND-TRUTH-LIKE FAILURES (v4)
  Test#  Task                          Issue
  ─────  ────                          ─────
   42    mrsd_computation              not grounded — no species/NOAEL in output
   89    mrsd_computation              not grounded
  103    mrsd_computation              not grounded

[Show all 12 cases →]

CHECKER DEFINITION
  Module: mrsd_verifier.py
  Citation: FDA 2005 Estimating the Maximum Safe Starting Dose
  Pass criterion: |stated MRSD - computed MRSD| / computed < 10%
```

**Drill-down by task** flips the view: show per-task per-checker matrix (e.g., "skeleton task: A passes 84%, A2 N/A, B4 N/A").

---

## Authoring a new task generator (modal flow)

When the user clicks "+ New Generator" on the Task Generators tab:

```
New Task Generator                                                       ✕

Step 1: What does this task teach the model?
────────────────────────────────────────────
[ free-text 2-line explanation, used as docstring ]

Step 2: Pick or define the checker
────────────────────────────────────────────
○ Existing checker:  [ mrsd_verifier ▾ ]
● New checker:       [ author in code, this dialog stages the contract ]

   Pass criterion (one sentence):
   [____________________________________________]

   Test fixtures:
   [+ Add passing example] [+ Add failing example]

Step 3: Sampler space
────────────────────────────────────────────
   Parameter         Type        Values
   [___________]    [select ▾]   [_________]    [+ Add param]

Step 4: Prose realizer
────────────────────────────────────────────
   Number of prose variants (recommend ≥3):    [ 3 ]
   Example template (user prompt):
   [____________________________________________]
   Example template (assistant output):
   [____________________________________________]

Step 5: Domain guardrails (exclusions)
────────────────────────────────────────────
   [+ Add exclusion]   e.g. "exclude oncology — ICH S9 path differs"

[Generate 50 samples for review]   [Save & generate full pool]
```

**Why this matters:** the v1 doc treated dataset collection as the primary creative act. In v2, the *generator* is the primary creative act — defining a task is defining a sampler + a checker. The dialog makes the contract (checker + sampler) explicit.

---

## What stays from v1 (no changes)

- Side nav layout, header, color tokens
- **Dataset tab** — real prose scraping (EMA EPAR, FDA NDA, TGA AusPAR, Health Canada SBD) — actively used for v8+ distribution-shift enrichment
- **Training Pairs tab** — pair-by-pair SFT review for the real-prose corpora; the new synthetic generators bypass this surface entirely (they have their own auto-verification)
- **Deploy tab** — adapter registration, A/B routing

---

## Build priority for Claude Design

If shipping incrementally, build in this order:

1. **Evaluate v2** (highest leverage) — once v6 finishes, the regulatory team needs a way to *see* the v2 checklist pass rates. Without this surface, the training run is invisible. Existing eval is ROUGE-L-centric and misleading.
2. **Task Generators tab** — closes the loop on "where does the corpus come from"; lets the regulatory scientist audit + re-run generators without ML-engineer help.
3. **Fine-Tune pipeline view** — replaces the v1 single-config form. Required before launching v7 with non-engineer oversight.
4. **DPO Pairs tab** — needed before v7 training; medium-effort because the diff viewer is novel.
5. **Authoring modal** — last, because the 5 existing generators cover the v2 checklist; adding new ones is a v8+ concern.

---

## Data flow (for Claude Design backend wiring)

All four new/replaced surfaces read from existing artifacts:

| UI surface | Backend source | API endpoint to wire |
|---|---|---|
| Task Generators list | `data/regulatory_training/tasks/task[5-9]_*.jsonl` + checker imports | `GET /api/regulatory/generators` |
| Task Generators detail | Re-run `scripts/baseline_v6_task_quality.py` | `GET /api/regulatory/generators/:id/stats` |
| DPO Pairs list | `data/regulatory_training/dpo/*.jsonl` | `GET /api/regulatory/dpo/pairs` |
| Fine-Tune pipeline | `logs/train_v6_*.log` + `models/regulatory_llm_v*/eval_metrics.json` | `GET /api/regulatory/training/jobs` |
| Evaluate v2 | `evaluation/results/regulatory_v*/summary.json` | `GET /api/regulatory/evaluation/:version` |

The pipeline reference doc is `docs/20260512_REGULATORY_LLM_V6_V7_PIPELINE.md` — share with Claude Design as the architecture handoff.

---

## Open design questions for Claude Design

1. **Pipeline view orientation** — horizontal (shown above) vs vertical stages? Vertical may fit better with the side-nav width budget.
2. **Checker pass-rate visualization** — bar chart vs heatmap vs sparkline trend over versions? Suggest sparkline so v4→v6→v7 progression is visible at a glance.
3. **Live training metrics** — Stream via SSE (matches BioMate workflow panel pattern in `chat-with-artifacts.tsx`) or polling? Suggest SSE for parity with the rest of the app.
4. **Generator authoring modal** — defer to a code-first workflow (just docstring the new generator script, surface in UI after the file lands)? May be simpler than a full author-in-UI flow.

---

# Appendix A — Update for 2026-05-14 (post-v6 training)

Since this doc was written, three concrete changes shifted what the UI needs to render:

## A1. Eval numbers are real, not pending

The Evaluate v2 tab can use actual numbers in its first mockup — replace the "pending" placeholders. v6 results on the test split (236 examples):

| Checker | v4 baseline | v6 actual | Target | Status |
|---|---|---|---|---|
| adversity_language (B4) | n/a | **100.0%** (30/30) | ≥80% | ✓ +20pp |
| skeleton_completion (A) | 0% | **97.9%** (94/96) | ≥80% | ✓ +98pp |
| mrsd_computation (C1) | 0% | **92.0%** (46/50) | ≥70% | ✓ +92pp |
| tabulated_summary (A2) | n/a | **83.3%** (25/30) | ≥70% | ✓ |
| phase_gating (C2) | n/a | **70.0%** (21/30) | ≥80% | ⚠ -10pp |

These should be the bar-height values in the v6 column of the per-checker chart. Color coding stays as in the original spec (green ≥80%, amber 50-79%, red <50%).

The phase_gating drill-down should highlight the failure-mode cluster surfaced in the eval:
- 4/9 failures forgot **hERG (ICH S7B)**
- 5/9 failures forgot specific repeat-dose duration or carcinogenicity

This is exactly the kind of insight Drill-down was designed to surface — make sure the failure-mode clustering is visible at first glance (e.g., a small donut chart or grouped bar showing "which study was missed").

## A2. v7 column is deferred, not pending

The Evaluate v2 layout shows three columns: v4 / v6 / v7. v7 training was attempted but is **deferred** due to hardware constraints (DPO per-step time on sm_121 is impractical with the current TRL+PyTorch versions in the NGC container).

Two display options for the v7 column:
- **Option A:** drop the v7 column entirely until training works on better hardware. Cleanest but loses the visual hint that DPO is the next product step.
- **Option B (recommended):** keep the v7 column with a "Deferred — see notes" badge instead of "Pending bars". Add a one-line tooltip explaining the hardware constraint.

## A3. Fine-Tune pipeline view: v6 is now the terminal stage

The horizontal pipeline diagram in the original spec showed:

```
Base → v6 SFT → DPO pairs → v7 DPO
```

Update to reflect actual state:

```
Base → v6 SFT (✓ active) → DPO pairs (✓ 2,659 staged) → v7 DPO (deferred)
```

The v6 SFT card should show a green check + "Active in production" badge. The DPO pairs card should show the pair-count summary. The v7 DPO card should be visually subdued (dashed border, gray fill) with the deferred reason.

The "Active in production" state is new — it means the UI needs a way to see *which* adapter is currently being served. Add a small status pill in the page header:

```
Active adapter: regulatory_llm_v6 ✓
```

When v7 (or v8 etc.) eventually trains and promotes, this pill updates.

## A4. New tab content for v8 — Real-data scrapers

The Task Generators tab spec described 5 *synthetic* generators. v8 will add a **real-data** track via three scrapers (TGA AusPAR, Health Canada SBD, NMPA CDE). Add a second sub-tab under the Dataset tab (or a new "Real-data Scrapers" tab) with the same row-per-source layout:

```
Real-data Scrapers                                             [+ New Source]

┌────────────────────────────────────────────────────────────────────────┐
│ Source                Region    Docs    Status      Last Run            │
├────────────────────────────────────────────────────────────────────────┤
│ ○ TGA AusPAR          AU        0       Network-gated   never           │
│ ○ Health Canada SBD   CA        0       Network-gated   never           │
│ ○ NMPA CDE Review     CN        0       Network-gated   never           │
└────────────────────────────────────────────────────────────────────────┘
```

Each scraper has a "Run" button (disabled when network unreachable). Behind each row, the diff with the synthetic Task Generators is that real-data records can fail extraction quietly — surface a "skipped: section heading not found" counter prominently.

The China (NMPA) scraper is particularly important for product positioning. Add a language-stratification micro-chart inside the NMPA detail panel (zh-CN / bilingual / en breakdown).

## A5. China-readiness display element

NMPA is a growing market. When v8 ships, the active-adapter pill should optionally show region-coverage:

```
Active adapter: regulatory_llm_v8 ✓   Regions: FDA · EMA · NMPA
```

A user clicking the regions chip can see per-region eval pass rates side-by-side. This is a v8 concern, not v6 — but worth designing into the data model now so the pill component doesn't need a redesign later.

## A6. What is NOT changed from v1 spec

To save Claude Design re-reading the whole doc:

- **Side nav layout** — unchanged (Dataset / Task Generators / Training Pairs / DPO Pairs / Fine-Tune / Evaluate / Deploy)
- **Color tokens** — unchanged
- **Build priority order** — unchanged (Evaluate v2 first, Task Generators second, etc.)
- **API endpoint wiring map** — unchanged; add one new endpoint `GET /api/regulatory/active_adapter` returning the currently-served adapter version

---

## Open design questions added by this update

5. **Active adapter pill placement** — top-right of header, or inline with the Fine-Tune pipeline view, or both?
6. **Deferred-stage visual treatment** — dashed border + gray fill (suggested above) sufficient, or do we need a more prominent "blocked / future work" indicator?
7. **Failure-mode clustering chart** for checker drill-downs — donut, grouped bar, or simple count list with study names? Phase_gating is the canonical case (hERG missed 4/9 times) — design it once and reuse for other checkers.
