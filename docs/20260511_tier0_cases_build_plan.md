# Tier 0 Cases Build Plan — 2024-2026 Marketing Hooks (2026-05-11)

Six Tier 0 cases identified in `20260511_marketing_case_studies_current.md` require some combination of new workflows, reference data extension, and validation scripts. This plan maps each case to a concrete build item, prioritizes them, and lays out the BioMate-internal validation steps to run *before* each build.

---

## The Six Tier 0 Cases — Build Requirements Mapping

| # | Case | What's needed | Existing workflow gap |
|---|---|---|---|
| A | Ivonescimab PD-1×VEGF | Bispecific format triage workflow | New: `bispecific_format_triage` |
| B | In vivo CAR-T | Multi-modality co-design (LNP × atlas × CAR) | New: `in_vivo_cart_codesign` (chain) |
| C | TIGIT graveyard | T-cell subset expression analysis | Existing atlas — extend rules |
| D | VERVE-102 base editing | In vivo base editing workflow | New: `in_vivo_base_edit_design` |
| E | GLP-1 race | Multi-receptor modality bake-off | Existing atlas+triage — extend cache |
| F | Q4 2024 FDA approvals | Retrospective validation panel | No new workflow; just data + script |

**Prerequisite for all six**: extend the offline reference cache in `atlas_expression_query` to cover ~25 modern targets. This is the gating item.

---

## Step 0 (Prerequisite): Reference Cache Extension

**What**: Add the following targets to `REFERENCE_CACHE` in `atlas_expression_query/main.nf` so the workflows can demo without live API dependency:

| Target | Why needed | Case |
|---|---|---|
| PDCD1 (PD-1) | T-cell-restricted; clean | A |
| KDR (VEGFR2) | Vascular endothelium; tumor angiogenesis | A |
| TIGIT | T-cell, NK, Treg | C |
| VEGF | Tumor-secreted; many normal tissues | A |
| GLP1R | Pancreatic α/β, gut L-cell, hypothalamic, cardiac low | E |
| GIPR | Pancreatic β, brain, adipose | E |
| GCGR (glucagon receptor) | Hepatocyte, pancreatic α | E |
| ANGPTL3 | Hepatocyte (Verve VERVE-201) | D |
| PIK3CA | Broad; flag breast indication | F |
| TFPI | Endothelial | F |
| CSF1R | Macrophage-restricted | F |
| IDH1 | Broad metabolic enzyme | F |
| NRG1 | Stromal; tissue-agnostic | F |
| LAG3 | T-cell exhaustion | future |
| TIM3 (HAVCR2) | T-cell exhaustion | future |
| DLL3 | Pulmonary/GI neuroendocrine + pituitary | already needed |
| GPRC5D | Plasma cell + taste + nail keratinocyte | already in Tier 1 |
| FAP | Tumor stromal fibroblast + BM stromal | already in Tier 1 |
| TROP2 | already in cache | — |
| MSLN | Mesothelial lining (pleural/peritoneal) | future |
| Lp(a) (LPA) | Hepatocyte-restricted | future |
| HER3 (ERBB3) | Epithelial; partner for HER2 | future |
| B7H3 (CD276) | Broad tumor expression + some normal | future |
| CLDN6 | Germline + tumor reactivation | future |
| KLK2 | Prostate-restricted | future |

**Effort**: ~1 day to compile from CELLxGENE + literature. No live API calls needed; values approximate to mean log1p CPM × 10 as in existing cache.

**BioMate-internal validation step before building**: Query the DB for any duplicate or overlapping workflow names. Run `atlas_expression_query` on each of the new targets after cache extension — confirm output structure matches expected shape. If any target shows unexpected expression pattern (e.g., GLP1R in CNS at unexpectedly high level), flag for cross-reference against published HPA data.

---

## Build Item 1: `bispecific_format_triage` (Case A — Ivonescimab)

### What it does
Given two targets, score every major bispecific format option (BiTE, CrossMab, DVD-Ig, KiH, nanobody fusion, mAb-mAb combo) based on:
- Cell-level co-expression of the two targets (atlas-driven)
- Required mechanism (cis-engagement vs trans-engagement)
- Affinity tuning needs (low affinity for one target, high for other)
- Biophysical constraints (size, valency, FcRn recycling)

### Architecture
```
INPUT: target_a (e.g., PD-1), target_b (e.g., VEGFR2), indication
   ↓
PHASE 1: Atlas query for both targets (use atlas_expression_query)
   ↓
PHASE 2: Co-expression analysis
   - Cell types co-expressing both → cis-engagement target
   - Cell types expressing only one → trans-engagement risk
   ↓
PHASE 3: Format scoring rules
   - BiTE: short half-life; high CRS; clean for trans-engagement
   - CrossMab: native IgG architecture; FcRn recycling; preferred for stable PD
   - KiH (Knob-into-Hole): bivalent on each arm; useful when affinity asymmetry needed
   - DVD-Ig: tandem variable domains; complex manufacturing; ADA risk
   - Nanobody fusion: small, fast PK; CNS-penetrant; ADA manageable with humanization
   - mAb-mAb combo: simplest; loses cis-engagement benefit
   ↓
PHASE 4: Output ranked format with rationale + manufacturing flags
```

### Why the framework would recommend bispecific TCE (CrossMab format) for PD-1×VEGF
- PD-1 on T cells + VEGFR2 on tumor vasculature (different cell types) → cis-engagement on tumor endothelium-T cell interface
- Both targets need normal tissue tolerance (VEGFR2 broad endothelial) → IgG-like half-life preferred over BiTE
- CrossMab is what Akeso/Summit actually built. The framework recovers Ivonescimab's architecture.

### Effort: 2-3 days
- Day 1: Format library with biophysical / mechanism scoring rules
- Day 2: Atlas co-expression query + scoring integration
- Day 3: Validation on 5 known bispecifics (blinatumomab BiTE, faricimab CrossMab, amivantamab KiH, glofitamab CD20×CD3, ivonescimab CrossMab)

### Success criterion
Workflow recovers the actual approved format for 4/5 known bispecifics from atlas + indication input alone.

---

## Build Item 2: `in_vivo_cart_codesign` (Case B — In vivo CAR-T frontier)

### What it does
Multi-modality co-design workflow for in vivo CAR-T. Combines:
- Atlas-driven CAR target safety (`modality_triage`)
- LNP tropism design (`lnp_formulation_optimization`)
- CAR construct architecture (`cart_construct_design`)
- Fratricide analysis: LNP must not transfect the cell type expressing the CAR target (e.g., CD19 LNP must avoid B-cell transfection)

### Architecture
```
INPUT: target_antigen, indication, in_vivo_target_cell (T cell / NK / macrophage)
   ↓
PHASE 1: Atlas check on CAR target (existing modality_triage)
   ↓
PHASE 2: LNP tropism analysis
   - Which cell types will the LNP transfect?
   - Spleen-targeted LNP (C12-200): preferred for T-cell access via splenic recirculation
   - T-cell-specific LNP (anti-CD7 / anti-CD3 conjugated): more selective
   ↓
PHASE 3: Fratricide check
   - If LNP transfects cell type expressing CAR target → FRATRICIDE WARNING
   - If LNP transfects B cells AND target is CD19 → CAR-T will kill its own delivery cells
   ↓
PHASE 4: CAR construct (existing cart_construct_design)
   - With suggestion: shorter persistence preferred for in vivo (avoid chronic LFTs)
   - 4-1BB vs CD28 costim choice informed by atlas tissue persistence requirement
   ↓
PHASE 5: Output integrated design package
```

### Effort: 3-4 days
- Day 1: LNP tropism scoring rules (based on Anderson, Whitehead, Sahay lab publications)
- Day 2: Fratricide analysis logic
- Day 3: Integration chain (call atlas_expression_query → modality_triage → cart_construct_design)
- Day 4: Validation on Capstan / Kelonia / Umoja published target/LNP combinations

### Success criterion
Workflow correctly identifies in vivo CD19 CAR-T fratricide risk (warns); validates Capstan CPTX-2309 (CD8-T-cell-targeted LNP + CD19 CAR) as architecturally sound.

---

## Build Item 3: `in_vivo_base_edit_design` (Case D — VERVE-102)

### What it does
Workflow for in vivo CRISPR base editing therapy design (cytosine base editor CBE or adenine base editor ABE):
- Target gene + desired edit (loss-of-function vs activation)
- Atlas-driven target tissue restriction check
- LNP / virus-like-particle (VLP) delivery selection
- Guide RNA design with off-target scoring
- Hepatocyte vs non-hepatocyte delivery routing

### Architecture
```
INPUT: target_gene, desired_edit_type, target_tissue, indication
   ↓
PHASE 1: Atlas tissue restriction (use atlas_expression_query)
   ↓
PHASE 2: Edit feasibility
   - Is there a known editable site (PAM availability)?
   - LoF stop codon → CBE (C→T) at exonic CAA→TAA, CAG→TAG, CGA→TGA
   - Activation/correction → ABE (A→G)
   ↓
PHASE 3: Delivery design
   - Hepatocyte (VERVE pattern): MC3-class LNP, IV
   - HSC ex vivo: electroporation + retransplant (Casgevy pattern)
   - Muscle: AAV9 or rh74 (Elevidys pattern)
   - CNS: intrathecal LNP or AAV9
   ↓
PHASE 4: Off-target scoring
   - Use crisprScore (existing) for guide RNA scoring
   - Atlas check: any off-target gene with overlapping critical-tissue expression?
   ↓
PHASE 5: Output design + IND-readiness checklist
```

### Effort: 3-4 days
- Day 1: Edit-type rules (CBE vs ABE vs prime editing)
- Day 2: Delivery vehicle decision logic
- Day 3: Integration with existing crisprScore + atlas_expression_query
- Day 4: Validation on VERVE-101/102 (PCSK9), VERVE-201 (ANGPTL3), Beam BEAM-101 (HBG1/2 for sickle cell)

### Success criterion
Workflow recovers Verve's actual design for PCSK9 (CBE, LNP, IV, hepatocyte) and Beam's design for sickle cell (ABE, ex vivo HSC).

---

## Build Item 4: GLP-1 Multi-Receptor Bake-off (Case E)

### What it does
Not a new workflow — a *demo script* that runs the existing `atlas_expression_query` + `modality_triage` workflows on all three GLP-1 family receptors (GLP1R, GIPR, GCGR) and produces a comparison output:

```
            GLP1R   GIPR    GCGR
Gut         HIGH    LOW     LOW
Pancreas    HIGH    HIGH    HIGH (α-cell)
Brain       MOD     MOD     LOW
Heart       LOW     LOW     LOW
Bone        LOW     MOD     LOW
Adipose     LOW     HIGH    LOW
```

The script then asks: for an obesity drug, which receptor combination + modality maximizes therapeutic effect / minimizes off-target?
- GLP1R alone (semaglutide): GI side effects dominant
- GLP1R + GIPR (tirzepatide): better tolerance (GIPR may mitigate GI)
- GLP1R + glucagon (retatrutide): risk of hyperglycemia
- mRNA-encoded GLP1R agonist: tissue-restricted via LNP

### Effort: 1 day
- 1 hour: add GLP1R, GIPR, GCGR to reference cache (done in Step 0)
- 4-6 hours: comparison script + demo notebook
- Demo output: side-by-side modality scores for sema/tirz/reta/orforglipron

### Success criterion
Comparison output recovers the known pharmacology: tirzepatide has better tolerance than semaglutide due to GIPR co-engagement, retatrutide has hyperglycemia risk from glucagon.

---

## Build Item 5: Q4 2024 FDA Approval Retrospective Validation (Case F)

### What it does
Run the framework on all 7 Q4 2024 approvals identified in the marketing doc. Validate that BioMate's triage matches the approved label profile:

| Drug | Target | Modality | Atlas verdict expected |
|---|---|---|---|
| Itovebi (inavolisib) | PIK3CA | Small molecule | druggability OK; flag hyperglycemia (atlas: pancreas + adipose PIK3CA) |
| Tryngolza (olezarsen) | APOC3 | GalNAc-ASO | VIABLE; clean hepatocyte restriction |
| Hympavzi (marstacimab) | TFPI | mAb | VIABLE; endothelial-restricted |
| Voranigo (vorasidenib) | mut-IDH1 | Small molecule | druggability route (mutant-specific) |
| Bizengri (zenocutuzumab) | NRG1 (HER2×HER3) | Bispecific | tissue-agnostic; bispecific format correct |
| Vyloy (zolbetuximab) | CLDN18.2 | mAb | VIABLE (gastric epi dose-limiting; matches label gastritis warnings) |
| Niktimvo (axatilimab) | CSF1R | mAb | macrophage-restricted; on-mechanism |

### Effort: 2 days
- Day 1: Run atlas_expression_query + modality_triage on each target, save outputs
- Day 2: Compare to FDA-approved label safety profile; document matches; identify any gaps

### Success criterion
≥6/7 triage outputs match the documented label safety profile (gives marketing the "we predicted every Q4 2024 approval" claim).

---

## Total Effort Summary

| Item | Days | Order |
|---|---|---|
| Step 0: Reference cache extension | 1 | first |
| Build 1: bispecific_format_triage | 2-3 | parallel |
| Build 2: in_vivo_cart_codesign | 3-4 | parallel |
| Build 3: in_vivo_base_edit_design | 3-4 | parallel |
| Build 4: GLP-1 bake-off demo | 1 | after Step 0 |
| Build 5: Q4 2024 retrospective | 2 | after Step 0 |
| **Total (serial worst case)** | **12-15 days** | |
| **Total (parallel agents)** | **5-6 calendar days** | |

---

## Pre-Build Validation Through BioMate

Before launching the agents, run the following BioMate-internal queries to validate the plan:

### V1. DB duplication check
```bash
sqlite3 backend/database/galaxy_ai_tools.db <<'EOF'
SELECT name, domain FROM workflows
WHERE lower(name) LIKE '%bispecific%format%'
   OR lower(name) LIKE '%in_vivo_cart%'
   OR lower(name) LIKE '%base_edit%'
   OR lower(name) LIKE '%in_vivo_edit%'
   OR lower(name) LIKE '%glp%'
   OR lower(name) LIKE '%multimodality%';
EOF
```
**Pass criterion**: zero hits on any of the proposed names. Confirms we are not duplicating.

### V2. Routing rule check
Search `frontend/server/galaxy-assistant.ts` for: "bispecific format", "in vivo CAR", "base edit", "GLP-1 race". Confirm none of the proposed user queries already route somewhere unexpected.

### V3. Existing workflow chainability
Confirm that the new workflows can call existing ones:
- `bispecific_format_triage` → `atlas_expression_query` ✓ (we have it)
- `in_vivo_cart_codesign` → `atlas_expression_query`, `modality_triage`, `cart_construct_design`, `lnp_formulation_optimization` ✓ (all exist)
- `in_vivo_base_edit_design` → `atlas_expression_query`, `crisprScore`, `crisprDesign` ✓ (all exist)

### V4. Atlas smoke test on new targets
Run `atlas_expression_query` on PD-1, VEGFR2, TIGIT, GLP1R, GIPR, GCGR, ANGPTL3, PIK3CA, TFPI, CSF1R, IDH1, NRG1 — confirm all return non-empty profiles after Step 0 cache extension. If any returns empty, the cache entry was missed.

### V5. Triage validation on Q4 2024 approvals
Run `modality_triage` on each Q4 2024 target after cache extension. Confirm verdicts match the FDA label safety profile. ≥6/7 match = green light to write the marketing case study.

### V6. Routing integration test
After workflows are built, add routing rules in `galaxy-assistant.ts`. Then issue test queries via the BioMate AI assistant:
- "Design a PD-1 × VEGF bispecific for NSCLC" → should route to `bispecific_format_triage`
- "How would I design an in vivo CAR-T for CD19?" → should route to `in_vivo_cart_codesign`
- "Base edit PCSK9 for hypercholesterolemia" → should route to `in_vivo_base_edit_design`

If routing fails, fix triggers before declaring the build complete.

---

## Plan Decision Gate

**If V1-V3 pass**: launch parallel agents for Builds 1, 2, 3. Step 0 cache extension can be the first agent's prerequisite or done by me directly (small effort).

**If V4 reveals empty profiles**: pause and complete cache extension before proceeding.

**If V5 fails on >2 of 7 Q4 approvals**: the framework has a systematic issue. Pause and reassess scoring rules. Do not build new workflows on top of a broken base.

---

## What Gets Pushed Per Build

Each agent should deliver:
1. The `.nf` workflow file
2. DB insertion (via Python `sqlite3` script returned in the agent message)
3. Smoke test result with expected output
4. Routing trigger phrases for `galaxy-assistant.ts`

I will personally do:
1. Step 0 reference cache extension (small, single-file edit)
2. The integrating routing-rules patch after all 3 workflows ship
3. The Q4 2024 retrospective validation panel run
4. The GLP-1 bake-off demo script
5. Documentation + git commits / push
