# Marketing & Product Discoverability Session — 2026-05-09

## What Was Done

This session covered two phases: strategic analysis and product implementation.

### Phase 1: Blog Survey & Gap Analysis

Read 25 blog screenshots from `~/Desktop/business/blog_collection/` covering FDA AI clinical trials, cryo-EM ROCKET, hard targets, drug discovery MPO, biomolecule design, physics vs AI FEP, protein revolution 2026, rare disease/TxGNN, single-cell virtual cell, siRNA design, and business strategy (Thiel/Godin/YC 2026).

Key finding after DB audit: **BioMate already has most of what the blogs point to as frontier**. The problem is discoverability, not capability.

Confirmed already in DB: OpenFE RBFE, TxGNN repurposing, STATE virtual cell, GEARS perturbation, REINVENT4, adaptive_trial_design (MAMS+RAR), simcyp_pbpk, nlmixr2, sirna_offtarget_analysis.

Confirmed gaps: siRNA generation step, cryo-EM atomic model building (Phenix/ModelAngelo), ADMET→REINVENT4 closed MPO loop, FDA audit trail on clinical outputs, routing discoverability for all the above.

Topic notes written to: `docs/20260509_blog_notes_*.md` (11 files).

Gap analysis + proposals written to: `docs/20260509_blog_survey_biomate_proposals.md`.

---

### Phase 2: Strategy + Implementation

Strategy document: `docs/20260509_marketing_positioning_strategy.md`

**The positioning claim:**
> "The only platform that runs IND-ready computational drug development end-to-end — from hit to §2.6 clinical narrative — in a single conversational interface."

Stack replacement value: $353K+/year vs commercial alternatives.

---

## Changes Shipped

### 1. Routing Rules — `frontend/server/galaxy-assistant.ts`

Added triggers so plain-English queries now route to previously hidden workflows:

| Workflow | Example triggers added |
|---|---|
| `Retrieve Topk Repurposing Drugs From Disease Txgnn` | "drug repurposing", "existing drugs for X", "rare disease treatment options" |
| `OpenFE Relative Binding Free Energy (RBFE)` | "FEP", "relative binding", "confirm affinity", "which ligand binds better" |
| `REINVENT4 Generative Lead Design` | "generate analogs", "scaffold hopping", "fix ADMET liability with new molecules" |
| `state_perturbation_prediction` | "virtual cell", "perturbation prediction", "cell response to drug", "CRISPR KO effect" |
| `gears_perturbation_prediction` | same triggers as STATE (offered as alternative for multi-gene KO) |
| `adaptive_trial_design` | "adaptive trial", "MAMS design", "O'Brien-Fleming", "interim stopping rules" |

Also added 5 few-shot query→workflow examples and expanded the drug discovery routing summary table.

### 2. Proactive Suggestions — `frontend/server/routes.ts`

Two suggestion blocks wired into both the AI analyze endpoint (~line 9680) and the findings card (~line 10008):

- **ADMET hERG/DILI/Ames flag** → AI offers REINVENT4 scaffold decoration with penalty function to generate 10–25 optimized analogs
- **Rare disease variant analysis** → AI offers TxGNN query to identify repurposable approved drugs; extracts gene symbols from findings text and names them in the offer

Detection patterns: regex on workflow name + findings text. Suggestions prepended to `next_steps` so they appear first in the recommended actions list.

### 3. Capabilities Page — `frontend/client/src/pages/capabilities.tsx`

New public route `/capabilities` (no auth required):
- **Section 1**: 6 job-cluster cards (IND Package, Lead Optimization, Cryo-EM, Rare Disease, Single-Cell, RNA Therapeutics) with descriptions and workflow badge chips
- **Section 2**: 8-row commercial comparison table with $353K+ stack replacement summary
- Linked from sidebar ("Capabilities" with BookOpen icon, `data-testid="button-capabilities"`)
- Uses only existing shadcn components (Card, Badge, Table, Button)

### 4. siRNA Design Workflow — new

**File**: `backend/nf-core-workflows/modules/biomate-ai-tools/sirna_design/main.nf`
**DB**: id=12924, domain=`molecular_biology`, name=`sirna_design_full`

Algorithm:
1. Parse mRNA (FASTA file, inline FASTA, or raw sequence); fallback: BCL2 demo
2. Optional region filter (all/coding/3utr/5utr via heuristic thirds)
3. Sliding window 19/20/21-nt; pad shorter mers to 21 per Elbashir 2001
4. GC filter: default 30–52%
5. Ui-Tei 2004 (4 features, max 4): pos-1 A/U, pos-19 G/C, antisense AU-rich[1-7], no repeats ≥4
6. Reynolds 2004 (8 features, max 8): GC 36-52%, no G@1, no GGG/CCC, U@10, A@3, A@19, A@AS10, Tm<20
7. Thermodynamic asymmetry bonus (max 1): dG5_antisense < dG5_sense (Schwarz/Khvorova 2003)
8. Sort by composite (max 13), tiebreak by GC proximity to 45%
9. Outputs: `sirna_candidates.csv`, `scoring_summary.json`, `design_report.txt`
10. Chains to: `sirna_offtarget_analysis` (seed scanning, miRNA mimicry, TLR motifs)

**Smoke test result (BCL2, 260nt)**:
- 305 candidates passed GC filter
- Tier distribution: A=5, B=142, C=147, D=11
- Top candidates: composite=10/13, GC 42–50%, all Tier A
- Scoring logic verified correct

---

## Audit Results

| Item | Status | Notes |
|---|---|---|
| Routing rules in galaxy-assistant.ts | Pass | 6 workflows, 5 few-shot examples, summary table |
| Proactive suggestions in routes.ts | Pass | 2 hooks (ADMET + raredisease), both endpoints wired |
| Capabilities page | Pass | Route registered, sidebar linked, no new deps |
| siRNA workflow logic | Pass | 305 candidates, correct tier distribution |
| TypeScript type check | Pass | 3 errors pre-existing, 0 new errors introduced |
| siRNA DB entry | Pass | id=12924, domain=molecular_biology |

---

## Known Open Items

- **ADMET → REINVENT4 closed MPO loop**: both tools exist in DB, connecting them as a chain workflow is the highest-impact remaining item
- **Cryo-EM atomic model building** (ModelAngelo + Phenix): reconstruction → depositable PDB gap still open
- **FDA audit trail JSON** on clinical trial workflow outputs: add to `clinical_trial_simulation` + `adaptive_trial_design`
- **Capabilities page** not yet tested in browser (dev server access needed)

---

## Files Changed

```
frontend/server/galaxy-assistant.ts     — routing rules + few-shot examples
frontend/server/routes.ts               — proactive suggestions (2 locations)
frontend/client/src/pages/capabilities.tsx  — new page
frontend/client/src/App.tsx             — route registration
frontend/client/src/components/app-sidebar.tsx  — sidebar link
backend/nf-core-workflows/modules/biomate-ai-tools/sirna_design/main.nf  — new
backend/database/galaxy_ai_tools.db     — id=12924 inserted
docs/20260509_blog_notes_*.md           — 11 topic notes files
docs/20260509_blog_survey_biomate_proposals.md   — gap analysis + proposals
docs/20260509_marketing_positioning_strategy.md  — strategy doc
```
