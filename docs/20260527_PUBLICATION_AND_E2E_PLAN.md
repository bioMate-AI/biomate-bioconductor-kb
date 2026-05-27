# Publication + E2E Plan — 2026-05-27

**Goal:** demonstrate the BioMate QC governance + auto-loop architecture is
*measurably* superior to silent-filtering pipelines, in a form publishable
in top-tier methods journals. Build the E2E test scaffolding needed for
the manuscript figures along the way.

---

## Strategy: one flagship + two domain follow-ups

| Paper | Venue | Audience | Status |
|---|---|---|---|
| **Flagship**: *Interactive Evidence-Graded QC Governance for Drug Discovery Workflows* | Nature Methods | Cross-domain methods | NEW — needs writing |
| **BioMate-Cryo**: *Evidence-Graded Interactive QC Governance for Single-Particle Cryo-EM* | Nature Methods OR Comm | cryo-EM community | DRAFTED at `research_repos/cryo_em_benchmark_paper/` |
| **BioMate-AutoLoop**: *Autonomous Parameter Convergence under Regulatory QC Constraints* | J Med Chem / Drug Discov Today | drug discovery | NEW — adapter + baselines exist |

**Why this split:**
- Flagship makes the methodological argument once with cross-domain proofs (cryo-EM, HTS, LNP, autoloop convergence)
- Domain papers go deep into one community's biology and reviewer expectations
- Cross-citation: flagship cites cryo for membrane discrimination depth; cryo paper cites flagship for the GOLD/SILVER/BRONZE framework
- No paper duplicates content; each has its own central contribution

---

## Tooling — leverage Galaxy-Dawn `claude-scholar/skills/nature-writing`

The skill encodes Nature-style structural patterns we'll reuse:
- **Abstract:** context → gap → approach → result → implication → boundary
- **Introduction:** field scale → bottleneck → prior attempts → unresolved gap → present study
- **Results:** evidence ladder (not chronological lab diary)
- **Discussion:** advance → interpretation → prior connections → constraints → outlook
- **Strict no-fabrication rule:** every number must trace to a logged result file

Agents writing prose use this checklist; I verify against it before commit.

---

## Experiments — 4 that anchor the manuscripts

### E1 — Silent filtering vs interactive governance
**Claim:** profile-blind QC discards valid data when sample biology deviates from default assumptions.

| Domain | Default profile | Domain-specific profile | Measured outcome |
|---|---|---|---|
| cryo-EM | `purified_protein` (drift ≤50 Å) | `membrane_protein` (drift ≤80 Å) | False rejection of membrane-like exposures (drift 58-74 Å) |
| HTS | strict (Z'≥0.5, SW≥2) | screening-grade (Z'≥0.4, SW≥1.5) | False plate rejections under marginal-but-real conditions |
| LNP | clinical (60-120 nm, EE≥85%) | research-grade (40-150 nm, EE≥70%) | False formulation rejections for early-dev batches |

**Output:** Figure 1 — false-rejection rate (y-axis) × sample-type × profile (x-axis). Single matrix figure shared by flagship + BioMate-Cryo.

### E2 — Auto-loop convergence vs single-shot
**Claim:** evidence-anchored auto-loop converges to all-green within ≤3 iterations on >50% of failing inputs, vs ~0% for single-shot.

**Method:** run `evaluation/adapters/autoloop_benchmark_adapter.py` with its 150 scenarios across 4 domains (ADMET 50, CYP-DDI 30, Docking 40, NCA-PK 30). Published baselines exist:
- ADMET: ~40% gate-pass@1 (TDC ADMET Group)
- CYP-DDI: ~30% gate-pass@1 (FDA DDI Guidance 2020)
- Docking: ~20% gate-pass@1 (DUD-E decoys)
- NCA-PK: ~50% gate-pass@1 (sparse-sampling protocols)

**Output:** Figure 2 — gate-pass@1 vs gate-pass@3 (auto-loop) per domain. Headline number for AutoLoop paper.

### E3 — Provenance grade ↔ remediation reliability
**Claim:** GOLD-anchored remediations produce reliably better convergence than BRONZE because GOLD thresholds reflect physical/regulatory reality.

**Method:** partition E2 results by provenance grade of the gates that triggered remediation:
- GOLD gates → measure Δ convergence rate
- SILVER → measure Δ
- BRONZE → measure Δ
- Expect GOLD ≫ BRONZE if hypothesis holds

**Output:** Figure 3 — Δ-convergence-rate × provenance-grade. Novel claim unique to BioMate (no other tool grades its thresholds).

### E4 — Audit-trail completeness
**Claim:** regulatory reviewer can reconstruct every threshold decision from BioMate run logs; this is not possible with CryoSPARC Live / RELION / standard tools.

**Method:** submit 10 BioMate runs (mix of cryo-EM, HTS, LNP, ADMET) + 10 matched runs through a baseline tool to a mock FDA review template. Score 0-1 per (run, decision-point) pair on completeness.

**Output:** Figure 4 — audit completeness, BioMate vs baseline, per run. Compliance argument for the flagship.

---

## E2E test scaffolding — mirror the cryo template

`frontend/e2e/cryoem-workflows-ux-e2e.e2e.ts` has 6 test IDs (CE-0..5):
| ID | Tests |
|---|---|
| 0 | API: QC profiles list |
| 1 | Full UI journey: chat → card → QC → execute → output viz |
| 2 | Secondary workflow variant |
| 3 | QC settings: profile selector + threshold override |
| 4 | Output viz: downloadable artifacts |
| 5 | Multi-session isolation |

**Phase 1 deliverable:** build the same suite for 3 representative domains —
- `hts-workflows-ux-e2e.e2e.ts` (simplest, gate-only)
- `admet-autoloop-workflows-ux-e2e.e2e.ts` (validates full auto-loop UI)
- `boin-clinical-trial-workflows-ux-e2e.e2e.ts` (regulatory display, no remediation)

These three span: gate-only display, full auto-loop, regulatory presentation. Together they validate the test template across the architecture's three modes.

**Phase 2:** expand to other 17 domains incrementally; not blocking for first manuscript submission.

---

## Execution waves

### Wave 1 (NOW, parallel) — data + outline + skill install (~6 hours)

- **Agent A** — E2 autoloop benchmark run: invoke the existing adapter, capture per-scenario convergence data, produce Figure 2 source
- **Agent B** — E1 silent-vs-governance experiment: design + run scenarios for HTS + LNP (cryo already done in existing draft), produce Figure 1 source
- **Agent C** — HTS E2E test template build (the simplest of 3) + adapt cryo test boilerplate
- **Agent D** — Install Galaxy-Dawn `claude-scholar/skills/nature-writing` skill + draft flagship paper Section 1 (Intro) using BioMate-Cryo's intro as starting boilerplate, generalized to cross-domain

### Wave 2 (after Wave 1, parallel)

- E3 partition + Figure 3 source
- ADMET autoloop E2E
- BOIN clinical trial E2E
- Draft flagship Results section using E1+E2 data
- Draft BioMate-AutoLoop paper Section 1+2 (Intro + Methods)

### Wave 3 (sequential)

- E4 audit-trail experiment
- Polish all three manuscripts via nature-polishing pass
- bioRxiv prep (figures, abstract, methods, supplementary)

---

## What I will NOT do

- Per-workflow papers for the 17 specialty domains. Reviewers see them as redundant.
- E2E for all 20 domains right now — diminishing returns; do the 3 representative ones first.
- Fabricate any numbers. Every figure value must trace to a logged result file. nature-writing skill enforces this; I enforce it on commit.
- Push to dev or sync during paper work. Manuscripts and data live in `research_repos/` and `evaluation/results/` — no deployment risk.

---

## Naming conventions

```
research_repos/
├── flagship_paper/                            ← NEW
│   ├── manuscript/MANUSCRIPT_DRAFT.md
│   ├── figures/{e1,e2,e3,e4}/
│   ├── tables/
│   └── results/                                ← raw logged data
├── cryo_em_benchmark_paper/                    (existing — finalize)
└── autoloop_benchmark_paper/                   ← NEW
    ├── manuscript/MANUSCRIPT_DRAFT.md
    ├── figures/
    └── results/

frontend/e2e/
├── cryoem-workflows-ux-e2e.e2e.ts             (existing — model template)
├── hts-workflows-ux-e2e.e2e.ts                ← NEW
├── admet-autoloop-workflows-ux-e2e.e2e.ts     ← NEW
└── boin-clinical-trial-workflows-ux-e2e.e2e.ts ← NEW
```

---

## Honesty commitments

1. **Provenance grade transparency.** Every BRONZE-graded gate (docking thresholds, pbpk_cl_min, etc.) will be flagged in the relevant manuscript as "operational heuristic without peer-reviewed cutoff." Not hidden.
2. **Negative results published.** If E3 shows GOLD gates don't outperform BRONZE → publish that. It would actually be more interesting than the predicted result.
3. **Reproducibility.** Adapter code + scenario data + result CSVs ship as supplementary material. Pre-print to bioRxiv before journal submission so it's frozen.
4. **No re-running until happy.** First-pass benchmark numbers are the headline numbers. Re-running until cherrypicked is forbidden.
