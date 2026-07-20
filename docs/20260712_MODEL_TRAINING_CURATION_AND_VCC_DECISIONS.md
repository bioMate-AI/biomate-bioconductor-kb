# Internal Model Training, Data Curation Feasibility & Virtual Cell Challenge — Decisions

**Date:** 2026-07-12
**Scope:** Consolidates the session's decisions on (1) what internal model training to do now, (2) whether/how to curate the type-I-IFN/STING variant-effect atlas and whether it's feasible for us, (3) the Virtual Cell Challenge verdict, and (4) whether the VCC dataset is useful.
**Frame (established earlier this session):** Don't compete on the crowded axis (single-cell foundation models on public data, where FMs lose to simple baselines). Own the type-I-IFN/STING franchise, entered at monogenic interferonopathies, with a **functional variant-effect atlas** as the curated moat. The orchestration platform + auto-update are the data-generation engine that feeds small, specialized, owned-data models.

---

## 1. Internal model training — two tracks, both on owned/curated data

**Rule:** don't train on public data everyone has; train small specialized models on data you uniquely own or curate.

### Track A — Orchestration models (start now; cheapest; compounding data moat)
- **Routing + parameter-extraction fine-tune** ("Layer-4-lite"). Contrastive embedding fine-tune on `(intent → workflow)` and `(context → params)` pairs from **failing benchmark cases + dev session traces + deterministic-routing logs**. Target ~80% → ≥85% routing. Small compute (DGX Spark / spot, hours).
- **Why first:** improves the product directly *and* is self-reinforcing — every run and every twice-weekly auto-update (that grows the catalog) generates more training pairs. This is the flywheel made concrete: platform + auto-update → traces → model → better platform.

### Track B — Autoimmune models (the defensible science; NOT an FM-on-public-data)
- **Functional variant-effect predictor for the type-I-IFN/STING axis** — a calibrated, multi-evidence classifier anchored to the ISG readout, **benchmarked against AlphaMissense/EVE**. Small specialized model on data we curate (the moat), not a leaderboard FM. Publishable; commercially wired to JAKi/STING programs.
- **SLE Geneformer multi-task adaptation** (cross-disease CE + pathway regression) — **secondary** publication/credibility piece; ship only if it beats the trivial baseline (mean-expression / PCA-logistic) with deconfounded ASW. A paper, not a product bet.

### Sequencing
1. **Now:** routing/param fine-tune (Track A).
2. **Now, parallel:** functional variant-effect model (Track B) — prove it beats AlphaMissense.
3. **Next:** SLE multi-task adaptation *iff* it beats baselines.
4. **Virtual Cell Challenge:** not in the training program (see §3).

**Through-line:** every model is small, specialized, and sits on data we own or curate. The Challenge is the opposite pattern (big model, public data, everyone competing) → off-strategy.

---

## 2. Curating the variant-effect atlas — how, and is it feasible?

**Verdict: yes, feasible — and the first, most valuable version needs no wet lab.** It's not a big-data project; it's a focused, expert-guided aggregation-plus-prediction effort where curation *is* the moat. Scale is small: the IFN/STING axis is ~15–20 genes → the whole atlas is O(1,000s) of variants, not genome-wide.

### Three tiers of curation
- **Tier 1 — Literature + database aggregation (feasible now, ~weeks, no wet lab).** The functional answers for many variants already exist, scattered across interferonopathy case reports/functional papers ("patient with `TREX1` X → elevated ISG signature"; "`STING1` V155M → constitutive activation"). Curate by extracting `(gene, variant, functional effect, ISG readout, GOF/LOF)` from primary literature + **ClinVar, INFEVERS, gnomAD, UniProt, HGMD**. This is exactly what BioMate's own agentic literature-mining does (dogfooding the platform builds the moat and demonstrates the product).
- **Tier 2 — Computational prediction to fill VUS (feasible now, compute-only).** For variants with no published function: AlphaFold3 + ΔΔG stability, catalytic/nucleic-acid-binding/dimerization residue hits, conservation, pathway context. Extends literature ground truth genome-wide with confidence scores. **Tier 1 + Tier 2 alone = a publishable, defensible atlas. No lab required.**
- **Tier 3 — Wet-lab functional validation (physical moat; feasible at small scale, later).** ISRE-luciferase reporter or ISG qPCR: ~96 variants/plate, ~$50–200/variant. Precedent: 2025 *Nat Immunol* NLRP3 paper functionally calibrated **534 variants of a single gene** — the scale model and proof of publishability. Via collaborator lab / CRO / the cloud-lab + Opentrons DBTL loop we wired this session.

### Feasibility for us specifically
- **Yes for Tiers 1–2**, with one real dependency: **a domain expert** (interferonopathy immunologist/clinician) to normalize heterogeneous assays and validate calls — curation without expert review is noise. This is why the **faculty collaboration (Zhao et al. / interferonopathy clinician) is the feasibility enabler, not optional.** Compute and tooling we already have.
- **Tier 3 is feasible later, not required first.**

### Honest risks
- **Ground-truth scarcity:** functionally-characterized variants may number only low hundreds per pathway → build a *calibrated predictor + curated reference*, NOT a data-hungry deep model (that recreates the FM-loses-to-baseline trap).
- **Extraction quality:** LLM extraction gets ~80%; expert review mandatory for the rest.
- **Check no one's built it:** INFEVERS exists but isn't an ISG-calibrated functional atlas; verify no recent gene-specific effort before committing.

### De-risking pilot (before any big commitment)
**2-gene pilot: `TREX1` + `STING1`** (well-studied, many published functional variants). Aggregate published + ClinVar/INFEVERS/gnomAD → LLM-extract → expert-review → Tier-2 predictions for VUS → **benchmark against AlphaMissense/EVE**. ~2–4 weeks with an expert in the loop. If it beats AlphaMissense on those two genes, the pathway-scale atlas is justified; if not, weeks spent, not the company.

---

## 3. Virtual Cell Challenge — do not attend as a bet

The whole session thesis says skip it. The Challenge **is** the crowded, data-rich axis we walked away from: 1,200+ teams, perturbation-response prediction on public data, where — by Arc's own results and Ahlmann-Eltze (Nat Methods 2025) — **foundation models lose to pseudo-bulk + Wilcoxon**. Entering to *win* means beating a t-test with a model that even Arc's winners couldn't beat with big models — negative EV, and it contradicts the positioning we built.

**Nuance:** if a cheap credibility/ecosystem artifact is wanted, enter as a *few-day side effort* with the honest angle that matches what actually wins — **orchestration + ensemble + classical stats + QC**, framed as "hybrid orchestration beats the monolith." Do **not** route the internal training program into it. (Deadline ~Aug 20 2026; ~5 weeks out.)

---

## 4. Is the VCC dataset useful for us? — No

The Arc VCC 2025 dataset is **~300,000 scRNA-seq profiles of H1 human embryonic stem cells (hESC) under 300 CRISPRi gene knockdowns** ([Arc wrap-up](https://arcinstitute.org/news/virtual-cell-challenge-2025-wrap-up)). Three fundamental mismatches with our direction:

1. **Wrong cell type** — embryonic stem cells, not immune. No PBMCs/T cells, no type-I-IFN biology. Zero overlap with interferonopathy/autoimmune.
2. **Wrong task** — perturbation-*response* prediction (knock down gene → predict transcriptome), not variant-*effect* prediction (missense variant → IFN-pathway functional effect on ISG readout). Different problem shape; not our ground truth.
3. **Wrong perturbation modality** — CRISPRi is loss-of-function knockdown of a whole gene; interferonopathies are largely **gain-of-function missense** variants. Knockdown data can't model a GOF point mutation — opposite mechanisms.

It's off-axis on cell type, task, and mechanism simultaneously — and a perfect illustration of why the challenge itself is off-strategy.

**What data IS relevant instead:** the atlas ground truth is **literature functional annotations + ClinVar + INFEVERS + gnomAD** with measured ISG readouts (a different *kind* of data, not single-cell perturbation). If immune single-cell perturbation data is ever wanted, **NeurIPS 2023 (PBMCs)** and **GSE135779 (SLE PBMC)** are far more on-target than VCC's hESCs — but still not the variant-effect ground truth the moat needs.

---

## Sources
- Arc Virtual Cell Challenge 2025 wrap-up (dataset composition): https://arcinstitute.org/news/virtual-cell-challenge-2025-wrap-up
- FMs lose to linear baselines: Ahlmann-Eltze et al., *Nature Methods* 2025 (deeper evaluation of single-cell foundation models)
- Functional variant calibration precedent: NLRP3 534-variant functional map, *Nature Immunology* 2025 (doi:10.1038/s41590-025-02093-y)
- Related session docs: [[20260712_MULTIOMICS_SYSTEMSBIO_SHOWCASE_GOLD_STANDARDS]], [[20260712_SPEEDUP_SURVEY_AND_ADOPTION_PLAN]]
