# Data Harmonization — In-Depth Survey (for the BioMate cohort-harmonization decision)

**Date:** 2026-07-27
**Method:** deep-research harness (fan-out web search → source fetch → adversarial verification → synthesis). Claims below are verified (2–3 vote adversarial check).
**Purpose:** decide whether/how BioMate builds a `cohort_harmonization` pipeline, and what to leave to per-client model adaptation.

---

## Verdict (one line)
**The field splits cleanly: the *technical* harmonization layer is MATURE and benchmarkable; the *metadata/clinical-annotation* layer is the genuine UNSOLVED bottleneck.** So BioMate should productize a **select-and-evaluate technical pipeline** and treat metadata harmonization as a **human-in-the-loop, ontology-grounded, per-client-adaptable service** — not a fully automated step.

---

## 1. Technical harmonization — MATURE, but "no universal winner"
Batch-effect correction and cross-cohort/cross-platform integration are well-characterized by rigorous benchmarks:
- **scIB / Luecken 2022** (Nat Methods) — 16 integration methods, 14 metrics, >1.2M cells, 13 atlas-level tasks. Recommendation: **the embeddings from Scanorama, scANVI and scVI perform best**; label-aware methods (scANVI, scGen) benefit when cell-identity labels exist.
- **Tran 2020** (Genome Biology) — 14 methods; recommends **Harmony, LIGER, Seurat 3**, Harmony first-to-try (fastest). **Condition-dependent:** Harmony best for identical cell types across sequencing technologies; **LIGER best when cell types are non-identical** across datasets.
- **2025 Nat Methods multimodal benchmark** — 40 methods; confirms the core trade-off.
- **Bulk RNA-seq:** ComBat-seq (negative-binomial, count-preserving) is the standard for raw counts; limma `removeBatchEffect` / RUV for normalized data.

**Load-bearing consensus — there is NO universal winner.** Method choice is task-, dataset-, and modality-dependent, and **every method trades batch removal against biological-signal preservation** (over-correction is a real failure mode). Methods cluster:
- batch-removal-favoring: SAUCIE, LIGER, BBKNN, Seurat v3
- bio-conservation-favoring: DESC, Conos
- balanced: **Scanorama, scVI, FastMNN**

**Implication:** a harmonization pipeline must **select-and-evaluate** (run several methods, score, pick), never default to one tool.

### Evaluation harness (the standard, and how you detect over-correction)
Two competing objectives, measured separately (the scIB split):
- **Batch removal:** kBET, iLISI, ASW-batch, graph connectivity, PCR.
- **Biology conservation:** cLISI, ASW-celltype, ARI, NMI.
An over-corrected result scores high on batch removal but low on biology conservation — the split makes it visible. **This evaluation loop is the productizable, defensible piece** (it turns "we ran Harmony" into "we selected the method that maximized batch removal *without* erasing biology, and here's the score").

---

## 2. Metadata / clinical-annotation standardization — the UNSOLVED bottleneck
Mapping heterogeneous clinical/sample metadata to common ontologies (EFO, Cell Ontology, UBERON, CLO, BTO; schemas OMOP CDM, FHIR, CDISC SDTM, Phenopackets, HPO, Mondo) is the real blocker, because:
- sources use **free-text name labels, not ontology IDs**, and automation **plateaus**;
- **LLM-based mapping generalizes poorly to unseen terms** — ~**96% accuracy in-dictionary vs ~17% out-of-dictionary** `[UNVERIFIED — specific 96%/17% figures not traced to a primary source; the qualitative failure is well-documented]`, with **hallucinated ontology identifiers** and precision varying wildly by ontology type.

**Therefore this layer must combine deterministic, ontology-grounded mappers (e.g. `text2term`, MetaHarmonizer) with MANDATORY human curation — not LLM inference alone.** This is exactly the "metadata harmonization is manual everywhere" pain UCB's VanBaaren named, and it is *why* it's unsolved: it's not an algorithm gap, it's a grounding + curation problem.

---

## 3. QC / triage & provenance
Pre-analytical variability is the **largest single source of inter-lab difference** (larger than the assay). Provenance/reporting standards exist (BRISQ/SPREC for specimens; MIxS/MIAME for omics) but are inconsistently applied. A harmonization pipeline should enforce a **QC-triage gate** (is this dataset good enough to integrate?) with recorded provenance — the "triage/filter" step UCB described.

## 4. What consortia built (position on top, don't rebuild)
AMP AIM, 3TR/ADEx, ImmPort, HuBMAP, Human Cell Atlas, GTEx, TCGA each built harmonization infrastructure and released harmonized data + tools — but **metadata harmonization remains the acknowledged unsolved piece** across all of them. BioMate should ingest/position on top of these releases, not reinvent the technical layer.

## 5. Federated / privacy-preserving harmonization
For IRB/IP-locked data, federated batch-correction and federated tensor-decomposition methods harmonize across sites **without pooling raw data** (precedent: the 261-donor SLE tensor decomposition recovering the IFN program without pooling cells). This is the credible path for cross-institution harmonization and pairs with the per-client model-adaptation plan (L4 federated).

---

## Concrete implications — what the `cohort_harmonization` pipeline should (and shouldn't) include

**BUILD (mature, defensible, mostly assembly of what BioMate has):**
1. **A select-and-evaluate technical harmonization module** — run a menu (Harmony, scVI/scANVI, Scanorama, FastMNN, LIGER for single-cell; ComBat-seq for bulk), then **score every result with the scIB two-objective harness** (kBET/iLISI/ASW-batch vs cLISI/ASW-celltype/ARI) and **auto-select the method that removes batch without erasing biology**, with the over-correction check surfaced to a human. This is the productizable wedge — the *evaluation + selection*, not any single method.
2. **A QC-triage gate** with provenance capture (BRISQ/MIxS-style) — "is this good enough to integrate?"
3. **Deterministic, ontology-grounded metadata mapping** (text2term / EFO-CL-UBERON) with a **human-in-the-loop review UI** — never LLM-alone.

**LEAVE to per-client model adaptation (do NOT fully automate):**
- Metadata harmonization for a client's idiosyncratic conventions → a **per-client LLM adapter that PROPOSES mappings for human confirmation** (grounded in the deterministic mapper, guarded against hallucinated IDs). This is the L1/L2 Ludwig play and it's where the real client-specific value + moat is.

**DO NOT:**
- Ship a single-method "we ran Harmony" step (no universal winner; over-correction risk).
- Trust LLM-only metadata mapping (poor out-of-dictionary accuracy `[the "17%" figure is UNVERIFIED]`, hallucinated IDs — the latter well-documented).

---

## Bottom line for the build
BioMate already has most of the technical methods (cellmixs/Harmony, scVI/scANVI, MOFA+). The **missing, defensible piece is the select-and-evaluate + scIB scoring loop + QC-triage gate + human-in-the-loop ontology mapping** — a real product, not a commodity, because it operationalizes the field's unsolved bottleneck. Metadata harmonization stays human-gated and per-client-adaptable. This is a genuine wedge and the M1/M2 reproducibility-manuscript backbone.
