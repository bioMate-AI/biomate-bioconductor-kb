# Immune Multi-Omics Multi-Task LLM — 8 Task Definitions & Data Status

**Date:** 2026-10-02
**Purpose:** (1) Detailed, non-single-word description of each of the 8 task objectives
(input → output → label → why it matters). (2) The corrected data status: **every label is
already collected** — the remaining work is *wiring* (linking collected labels into the corpus
as supervised heads), NOT acquisition. (3) The one genuine gap (druggability/tractability channel).

**Correction recorded here (so it is not repeated):** earlier status markers (⚠️ "proxy / unlabeled",
🔴) on recognition / durability / inflammation / biomarker were *wiring* states. They were written in a
way that read as "data missing." That is wrong and is the recurring under-scoping error
([[feedback_verify_data_existence]]): the labels exist, verified on S3 below. A task not yet trained as
a head ≠ a task without a label.

Corpus bucket: `s3://knowledge-datasets-1759951976/` (region us-west-2).

---

## 1 · The 8 task objectives — detailed

The LLM produces **one shared multi-omic representation**; each task is a head / downstream scorer on
top of it. Grouped by what they do.

### Foundational representation

**1. Annotation (cell-type / cell-state identification)**
- **Predicts:** what kind of immune cell each cell is (CD4 T, CD8 T, Treg, B, NK, monocyte, DC, … down
  to activation states).
- **In → Out:** a cell's multi-omic profile → one of ~20–50 cell-state labels.
- **Label (collected):** curated cell-type ontology (CellTypist/Azimuth) on the corpus; also
  `immuno_oncology/Zenodo_5461803_Zheng_Tcell/` (Zemin Zhang pan-cancer T-cell atlas) as external atlas.
- **Why it matters:** everything downstream depends on correctly identifying immune states; also
  produces the cell-state composition features that drive stratification.
- **Status:** ✅ the FM's clean standalone win (+0.039 vs null). Field head-to-head (CellTypist/scANVI/
  scGPT) pending in the scaled run.

**2. Lineage** — *honest note:* as built, this head reuses the **same cell-type label as annotation**
(it is the linear-advantage comparator, not a distinct lineage taxonomy). Not a genuinely separate task
in the current system. Either fold into annotation or re-target to a real developmental-trajectory label.

### Target & therapy design

**3. Target-ID (therapeutic target nomination + confidence)**
- **Predicts:** which genes/proteins are good drug targets for a disease, and how confident we are.
- **In → Out:** disease immune-signature + multi-channel evidence → ranked target list with confidence.
- **Label (collected):** curated gold targets (Open Targets / DisGeNET / CollecTRI wet-lab-validated);
  evidence channels on S3 — `immune_llm_baseline/knowledge/` (PINNACLE context PPI
  `raw/pinnacle_embeds.zip`, STRING-SVD `string_svd_knowledge_hvg2000.npz`), genetics/L2G, perturbation-
  causal (`vcc2026/delta_corpus/`, `replogle_nadig/`), pathways, immunopeptidome.
- **Why it matters:** the bottleneck is target *confidence* (triangulation), not discovery. We fuse 7
  orthogonal channels + a measured virtual-KO screen, degree-null gated.
- **Status:** ✅ 7-channel fusion 0.813 > null; measured KO screen 0.85; FM additive +0.059 (coverage-gated).
- **GAP:** no **druggability/tractability** channel — see §3.

### Clinical outcome prediction

**4. Responder stratification (immunotherapy response)**
- **Predicts:** will this patient respond to a therapy (checkpoint-inhibitor responder vs non-responder)?
- **In → Out:** patient immune profile (pseudobulk / cell-state composition) → responder probability.
- **Label (collected):** clinical response (RECIST, R/NR) in the ICB cohorts —
  `immuno_oncology/GSE78220` (Hugo), `GSE91061` (Riaz), `GSE135222` (NSCLC), `GSE120575` (Sade-Feldman),
  `GSE115978`; plus the tigeR 11-cohort bulk set already staged.
- **Why it matters:** the central clinical question — who benefits from immunotherapy (~20–40% respond).
- **Status:** ✅ delivered by gene-set/PCA (field-competitive with TIDE/GEP18/IMPRES, leave-cohort-out).
  Raw FM embedding does **not** add here (batch-entangled) — we do not claim it does.

**5. Durability (response durability / survival)**
- **Predicts:** will the benefit *last* — durable response vs relapse/progression over time.
- **In → Out:** patient profile (baseline/longitudinal) → time-to-progression / long-term response.
- **Label (collected):** survival/outcome in the same ICB cohorts — GSE78220 OS, GSE91061 OS,
  GSE135222 PFS; perturbation leave-condition-out (Frangieh) as a mechanistic proxy; Cox survival head
  on TCGA OS/PFI.
- **Why it matters:** "responds" ≠ "stays responding"; distinguishing transient from durable benefit
  changes the treatment plan.
- **Status:** 🟡 **wiring, not missing** — labels collected; needs the survival head trained on the
  cohort OS/PFS columns (parse the `*_PatientFPKM.xlsx` / `*_raw.csv.gz` metadata → survival vector).

**6. Inflammation (disease-activity level)**
- **Predicts:** how active the immune/inflammatory state is (lupus flare vs managed, RA activity).
- **In → Out:** immune profile → disease-activity score / level.
- **Label (collected):** `autoimmune_sc_corpus/labels/activity_v2/` and
  `autoimmune_sc_corpus/curated/clinical_labels_queue.csv` (over the 14.5 GB curated
  `autoimmune_sc_corpus.h5ad`); DAS28 / SLEDAI indices.
- **Why it matters:** the autoimmune analog of stratification — monitoring and dosing depend on it.
- **Status:** 🟡 **wiring, not missing** — labels collected; needs the activity label joined to the
  expression corpus as a regression/ordinal head.

### Antigen & T-cell specificity

**7. Presentation (antigen presentation / HLA-I ligand)**
- **Predicts:** will a peptide be displayed on HLA to T cells (a genuine HLA-I ligand), ideally
  conditioned on cell state.
- **In → Out:** peptide sequence (+ cell context) → presented / not.
- **Label (collected):** `immuno_oncology/HLA_Ligand_Atlas/` (MS-eluted ligands) + decoys; SysteMHC/TESLA.
- **Why it matters:** the first step of any T-cell response — neoantigen discovery, vaccines, TCE design.
- **Status:** 🟡 partial. Differentiation = **cell-state-conditional** presentation (NetMHCpan/MHCflurry
  can't model context). Needs the SOTA head-to-head.

**8. Recognition (TCR–antigen recognition)**
- **Predicts:** does a given T-cell receptor recognize a given peptide-MHC?
- **In → Out:** TCR (CDR3) + peptide-MHC → recognition probability.
- **Label (collected):** `immuno_oncology/VDJdb/vdjdb-2026-06-03.zip` + `IEDB/tcell_full_v3.zip`
  (TCR→antigen pairs); IMMREP for eval.
- **Why it matters:** maps which T cells respond to which antigens — central to TCR therapy, immune
  monitoring, mechanistic interpretation of a response.
- **Status:** 🟡 **wiring, not missing** — pairs collected; needs a per-sequence TCR/CDR3 encoder head
  (transfer task). Field-hard (unseen epitopes ≈ chance) — report honestly against NetTCR/ERGO/pMTnet.

### (retired as built)

**Biomarker** — the head as built regressed a self-supervised gene-set mean (circular: target ⊂ input).
**Real target is collected, not missing:** re-anchor to an **outcome label** (response/survival from the
ICB cohorts above) so the biomarker head predicts a clinically-anchored signature, not itself. Status
🟡 wiring.

---

## 2 · Corrected summary — labels are collected; the work is wiring

| Task | Prior marker | Truth | Collected label location | Remaining work |
|---|---|---|---|---|
| Annotation | ✅ | ✅ | corpus CellTypist/Azimuth; Zheng atlas | field head-to-head |
| Target-ID | ✅ | ✅ | knowledge/ channels + delta_corpus | add druggability (§3) |
| Stratification | ✅ | ✅ | ICB cohorts RECIST | — |
| Durability | ⚠️ "proxy" | 🟡 wire | GSE78220/91061 OS, GSE135222 PFS | train survival head on cohort metadata |
| Inflammation | ⚠️ "unlabeled" | 🟡 wire | autoimmune_sc_corpus/labels/activity_v2 | join activity label → ordinal head |
| Presentation | 🟡 | 🟡 | HLA_Ligand_Atlas | cell-state-conditional head-to-head |
| Recognition | ⚠️ "no label" | 🟡 wire | VDJdb + IEDB | build CDR3 encoder head |
| Biomarker | 🔴 circular | 🟡 wire | re-anchor to ICB outcome | swap self-target → outcome label |

**None of the remaining items is an acquisition.** Seven are "join a collected label to a head" or
"build an encoder." One (§3) is a small public download.

---

## 3 · The one genuine gap — druggability / tractability channel

Target-ID currently answers "is this gene causally real in the disease?" (evidence channels) but **not**
"is it drugged-able?" A target can be causally validated yet undruggable. We do **not** have a
druggability/tractability channel in `knowledge/` (verified: no DGIdb / Open Targets tractability /
Pharos artifact present; only PINNACLE PPI + STRING-SVD + genetics + perturbation + immunopeptidome).

**Fix (public download, not wet-lab):**
- **Open Targets tractability** buckets (small-molecule / antibody / PROTAC / clinical-precedent) per
  target — the standard druggable-genome annotation.
- **DGIdb** drug–gene interactions (existing drugs per target).
- **Pharos / IDG** target development level (Tclin/Tchem/Tbio/Tdark).

Add as an **additive gating channel**: target-ID outputs *(confidence, tractability)* so a nomination is
both "real" and "actionable." Small, deterministic, no model risk.

---

## 4 · Net effect on the scaled run

The 67M full-modality run should train **all 8 heads live** (not leave 4 dormant), because every label is
already on S3:
- survival head ← ICB cohort OS/PFS (durability)
- activity head ← autoimmune_sc_corpus activity_v2 (inflammation)
- CDR3 encoder head ← VDJdb + IEDB (recognition)
- outcome-anchored biomarker head ← ICB response/survival (replaces circular target)
- + annotation / target-ID / stratification / presentation already wired

Plus the druggability channel bolted onto target-ID (§3). This turns the "7/8 flagged" picture into
"8/8 trainable on collected data," which is the honest state.

Related: [[feedback_verify_data_existence]] · [[project_immune_system_of_record]] ·
[[project_immune_fm_scope_vs_collected]] · 20261001_IMMUNE_LLM_ADVANTAGE_AND_BENCHMARK_PLAN.md.
