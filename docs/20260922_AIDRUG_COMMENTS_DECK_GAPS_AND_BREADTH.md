# AI-drug commentary → BioMate execution, deck gaps, and breadth-beyond-early-R&D

**Date:** 2026-09-22 · **Inputs:** two 小红书 comments (可颂) on what AI drug discovery really is
(`~/Desktop/business/bioconductor_screenshot/AIdrug_comment{1,2}.jpg`) + the CN-EN client deck.
**Purpose:** does BioMate execute what the commentary describes; are the benefits in the deck; what to quantify for a
flyer; is the AstraZeneca/Biomni pharma-service breadth in the deck; and does BioMate do multi-agent orchestration.

## 1. What the commentary says (the "needs")
Not sci-fi "disease in → drug out." A **deterministic path through a huge search space**: find targets → screen
molecules → predict properties → optimize structure → decide which candidates deserve the next experiment.
**Multi-stage, multi-model** (AlphaFold/RoseTTAFold/DiffDock for structure/docking; GNN/Graph-Transformer/ChemBERTa
/MolBERT for property/activity; diffusion/VAE/autoregressive for design). A real candidate must balance
**activity · selectivity · solubility · toxicity · metabolism · stability · synthesizability · ADMET** =
**multi-objective optimization**. **A model's high score ≠ a real drug → validate experimentally.** The value:
**reduce blind trial-and-error; make every experiment more informative;** AI changes *"what's most worth doing next."*

## 2. Are the needs executed in BioMate? (honest, incl. today's findings)

| Commentary need | BioMate | Status |
|---|---|---|
| Find targets | target-ID (Open Targets…) | ◑ present |
| Screen molecules (docking) | `docking_autodock_vina` | ✅ real (1 verify run pending) |
| Predict properties / activity | ADMET panel, QSAR | ✅ ADMET dev-verified |
| Optimize structure (generation) | **REINVENT4 (built 2026-09-21)** | ◑ real-in-code |
| **Multi-objective optimization** | **MPO/GP-Pareto loop (built)** | ◑ real-in-code |
| Structure / protein-ligand | AlphaFold + docking | ◑ present |
| **Validate experimentally (DMTA)** | verify layer + assay-ingest/retrain | ✅ real |
| **Reduce blind trial-and-error** | QC gate blocks invalid runs; verify-before-advance | ✅ **core pitch** |
| FEP (binding free energy) | **OpenFE RBFE (built, replaced a fabrication)** | ◑ real-in-code |
| Generator fine-tuning + RL | **REINVENT4 transfer + staged-RL (built)** | ◑ real-in-code |
| **selectivity** | `proteome_selectivity_profiling` | ⚠️ **FABRICATED → fixing** |
| CYP DDI panel | `cyp_ddi_panel` | ⚠️ **FABRICATED → fixing** |
| solubility · metabolism · stability | scattered | ◑ verify per-endpoint |

**Bottom line:** BioMate executes the **core** of exactly what the commentary describes — multi-stage, multi-model,
multi-objective, verify-then-validate — and today's builds (generation, MPO, FEP, RL) closed the biggest gaps. **But
three workflows were *fabricating* results** (FEP fixed; `proteome_selectivity_profiling` + `cyp_ddi_panel` being
fixed now) — random numbers dressed as predictions. Until fixed, "selectivity" and the "CYP panel" cannot be claimed
honestly. A **repo-wide fabrication sweep + fix is in progress.**

## 3. Are the benefits reflected in the deck?
**Qualitatively, yes and precisely** — the commentary's core value *is* the deck's thesis:
generate → **verify** → learn · "no single opaque score decides a compound" (= multi-objective) · "verification
changed the answer" (= high-score ≠ drug) · "invalid runs stopped at the QC gate — where real cycle-time savings
come from" (= reduce blind trial-and-error). The narrative is dead-on.
**Missing: concrete numbers.** The benefits are stated qualitatively; a flyer/sales needs quantification.

## 4. Concrete numbers for the flyer (honest set)
**State now (real counts):** 4,017 workflows · 36 domains · 12k+ tools · 60+ data sources · ADMET 5 safety endpoints
(hERG·CYP·hepatotox·off-target·metabolic) · modalities small-molecule + peptide/macrocycle · docking ~3–8 min/run ·
multi-objective across 4 axes (affinity×SA×safety×developability).
**ROI numbers — require the pilot's retrospective run, do NOT invent:** enrichment factor (EF1%/BEDROC on LIT-PCBA),
% runs stopped before wasted compute, cycle-time reduction, hit-rate lift vs baseline. Frame these as
*"validated during the pilot on your data,"* not asserted.

## 5. Is the AstraZeneca + Biomni pharma-service breadth in the deck?
- **Strategy deck** (`20260921_BIOMATE_PHARMA_GUANGDONG_DECK.md`): YES — has the AZ (ChatInvent/REINVENT4/AiZynthFinder,
  MCP) + Biomni/Phylo (Ono/Chugai) coverage slides + the intel doc.
- **CN-EN CLIENT deck** (the one going to the client): **NO** — competitors were condensed to a single appendix slide;
  AZ's and Biomni's *workflows/services* are not listed. **Action: add a "pharma workflow coverage" page** (AZ + Biomni
  workflows + more pharma-relevant workflows) — the page you requested; not yet added.

## 6. Does BioMate do multi-agent orchestration (like Virtual Biotech's simultaneous agents)?
- **Virtual Biotech** ran **11 standing agents + ~37,000 ephemeral per-trial agents simultaneously** for early-R&D
  research (a 55,984-trial meta-analysis).
- **Does BioMate do it today? NO (not as a shipped feature).** BioMate has NextflowComposer (workflow generation),
  lane-arbiter routing, the QC/verify auto-loop, an agentic composer — a **single-orchestrator + workflow-execution**
  architecture, not a standing team of simultaneous specialist agents + an independent reviewer running in parallel.
- **Can it? Yes — buildable, not built.** BioMate is **MCP-native**, and the leverage doc (N8) scopes exactly this:
  adopt the Virtual-Biotech pattern (CSO + specialists + reviewer + ephemeral fan-out) on BioMate's MCP tools; a public
  re-impl exists (github.com/gliaropoulos/virtualbiotech).
- **Is it in the deck? Yes — and it OVER-CLAIMS.** Client-deck S11 ("AI 科学家团队规划与调用工具，独立审核者复核") implies
  a shipped agent team; per the honesty audit this is the **adopt-pattern, not shipped (⚠️ item S11).**
  **Action: BUILD the multi-agent orchestration on BioMate MCP, or reframe S11** to what's real (the QC/verify
  auto-loop + adversarial review, which we *did* run on the peptide program).

## 7. Breadth beyond early R&D (survey in progress)
The commentary + the Biomni/Chugai model (**single-cell · human genetics · disease biology · target evaluation**) and
AZ (BIKG target-ID, clinical-trial retrieval, pharmacovigilance) show pharma is serviced **far beyond target→lead**.
BioMate's genuine strength is exactly here — **4,017 workflows across 36 domains** (transcriptomics 865, genomics 369,
epigenomics 133, single-cell, proteomics 113, systems biology, immunology, metabolomics, cryo-EM…). A dedicated
survey (human genetics/GWAS, functional genomics, single-cell/spatial, translational/biomarkers, safety/tox, DMPK/PBPK,
clinical simulation, RWE/pharmacovigilance, NGS pipelines) is running; results + the deck-breadth additions land next.
*(This is a strong story: the client asked for early-discovery, but BioMate services the whole R&D org — like Biomni at Chugai.)*

## 8. Action items
1. **Fix fabrications** (selectivity, CYP panel, any others) → real or honest-null. *(in progress)*
2. **Add to the CN-EN client deck:** (a) a **pharma workflow-coverage page** (AZ + Biomni + more), (b) a
   **quantified-benefits/flyer block** (real counts now + pilot-validated ROI), (c) a **breadth-beyond-early-R&D page**
   (human genetics, single-cell, biomarkers, safety, clinical — BioMate's omics strength).
3. **Multi-agent (S11):** build the MCP-native agent orchestration, or reframe honestly.
4. Keep every number/claim honest; no fabricated benefits.

## Change log
- 2026-09-22 — created; documents the commentary↔BioMate mapping, deck gaps, AZ/Biomni-coverage, multi-agent
  assessment, and breadth-beyond-early-R&D plan. Fabrication-fix + pharma-survey agents running.
