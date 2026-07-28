# Autoimmune Patient Stratification — Corrected Strategy, Evaluation & Publication Plan

**Supersedes:** the July 2026 "Autoimmune Patient Stratification: Landscape, Evaluation Framework, and Monetization Assessment" draft.
**Why a rewrite:** that draft scoped BioMate to a single capability (LC-MS immunopeptidomics) and therefore concluded that antigen identification is BioMate's only defensible position. A capability survey of the production catalog (4,000+ workflows / 34 domains, verified live) shows BioMate already runs the **entire multimodal stratification stack** the field uses. That changes the conclusion.
**Date:** 2026-07-27

---

## 0. What the previous draft got right — keep it

The prior analysis is rigorous and its spine is retained:

1. **Five sequential gates.** Gate 3 (predictive vs prognostic — does the marker change *which* treatment is better, tested via a **biomarker × treatment interaction**, not a main effect) is where the field dies. PROFILE (interaction 1%, p=0.944) is the canonical failure.
2. **Do not build a per-test product.** The per-test / clinical-LDT route has a demonstrated ceiling (Exagen: $444/test, 59% GM, unprofitable at ~$70M revenue; Scipher: ~$100M implied for the whole platform after a decade + CMS + Quest, then acquired a drug because it could not monetize stratification as stratification).
3. **Revenue is in selling *capability* to drug developers** — $15–40M recurring, milestone-gated (Immunai's three top-10 pharma deals in 18 months; Repertoire–Lilly; Adaptive).
4. **The monetizable position is upstream infrastructure**, defensible only if it is a **gate-3 enabler** rather than another gate-2 signature.

### The economics, stated precisely (a common misread)
"$100M" is **not** smaller than "$15–40M." They are different quantities:
- **$100M = a ceiling** — the *total equity value* of the entire stratification-product company after a decade.
- **$15–40M = a unit** — *one* recurring pharma-development contract, stackable (5 active relationships ≈ $100–200M *annual* bookings; at services/platform multiples that is a company worth many times $100M).

The product route's *entire* value ≈ one services company's *annual* revenue. Capital-light + fast (services) beats capital-heavy + decade-long (CLIA labs, sales force, RWE). **This is the whole argument for the services position — and it is unchanged.**

---

## 1. The correction — BioMate is not an LC-MS tool

The field's stratification workflow spans single-cell, multi-omic integration, immune profiling, repertoire, spatial, genetics, methylation, and antigen resolution. BioMate covers **all of it** (verified live against the production catalog):

| Landscape requirement | Public substrate the field uses | BioMate capability (in catalog) |
|---|---|---|
| Single-cell immune atlases | AMP AIM 3D multi-omic atlas | scRNA multi-sample **chain**, annotation, trajectory/pseudotime, cell–cell communication |
| Multi-omic integration → **endotypes** | PRECISESADS / SLE 3–5–8-endotype schemes | **MOFA+ multi-omics integration chain** (factor analysis + biomarker discovery + clustering) |
| **Antigen resolution** ("closest to the atlas thesis" — Adaptive's TCR–antigen map) | VDJdb, IEDB, McPAS-TCR, HLA Ligand Atlas | **`airrflow`** (TCR/BCR repertoire) + **`hlatyping`** + **`epitopeprediction`** + **LC-MS immunopeptidomics** |
| Immune profiling | flow / CyTOF cohorts | **CyTOF (cytofWorkflow) chain**, bulk deconvolution (`rctd`) |
| Spatial (3D atlas) | AMP AIM spatial | `spatialvi`, spatial deconvolution |
| Genetics → cell type | DICE, OneK1K, eQTLGen | `nf-core/gwas`, **GMRP**, MAGMA, LDSC, TorchGWAS |
| Methylation | 3TR methylomics | `methylseq` |
| **Harmonization** (the field's stated blocker) | cross-cohort meta-analysis (ADEx) | batch correction (`cellmixs`), integration |
| Disease signatures (ISG/IFN — SLE, CAR-T selection) | interferon program | Transcriptomic Biomarker / gene-set scoring |
| Target/biomarker prioritisation | Open Targets | **target_scorecard_ranker** (OT two-layer method) |

**Conclusion:** BioMate is the **multimodal stratification + antigen-resolution orchestration layer** — not an antigen-ID point tool. This is materially stronger than the prior draft's premise, and it re-opens positions the draft ruled out.

---

## 2. Corrected positioning

> **BioMate is the reproducible, multimodal orchestration layer that lets drug developers produce, validate, and *re-produce* gate-3 stratifications — across every modality the field uses, including the TCR↔HLA↔peptide antigen-resolution loop.**

### Why this survives the two hardest objections
- **"Software-only is commoditized by public data" (the Immunai/wet-lab objection).** The moat is not any single model or dataset — it is *reproducible multimodal orchestration + harmonization across heterogeneous cohorts*, which is precisely the field's stated blocker ("absence of large, harmonized, longitudinal cohorts… not the absence of algorithms"). Breadth across 9 modalities is not something a single-modality shop can assemble on public data quickly. This is a workflow/reproducibility moat, not a data-hoarding one.
- **"The public substrate expands faster than the moat" (AMP AIM / 3TR / ADEx).** Position *on top of* these releases as the layer that ingests, harmonizes, and gate-3-validates them — the tool that turns the 3TR/ADEx and AMP AIM releases into trial-ready stratifications. Their expansion is our fuel, not our competition.

### What changes vs. the prior draft
- The prior "only antigen ID is defensible" narrows to a subset of what BioMate can sell. BioMate can be the **full-stack gate-3 enabler**, of which antigen resolution is one (high-value) lane — and BioMate already has that lane (airrflow + hlatyping + epitopeprediction + LC-MS), which nobody knows.
- The external suggestion — *"train models for patient stratification and biomarker ID for pharma development"* — is correct **as a service, targeting gate-3, leveraging the multimodal breadth** — not as a per-test product and not as a single commoditized model.

---

## 3. Evaluation & Implementation Plan — proving the capability to clients

Two tracks: **capability demonstrations** (public data, fast, credibility) and **client pilots** (named accounts, scoped, revenue).

### Track A — Capability demonstrations on public data (no biobank/IRB blocker)
Each runs on existing workflows and public cohorts, and is explicitly scored against the five gates.

| # | Demonstration | BioMate stack used | Public data | Gate shown |
|---|---|---|---|---|
| A1 | **Reproducible multimodal endotyping** of a public autoimmune cohort | MOFA+ integration chain + scRNA + CyTOF | ImmPort / GEO / 3TR-ADEx on release | Gate 0 (partition real: out-of-cohort label transfer + longitudinal stability) |
| A2 | **Endotype reproducibility audit** — re-derive the published SLE 3 vs 5 vs 8-endotype schemes on independent data | MOFA+ + clustering + `cellmixs` harmonization | PRECISESADS-adjacent public data | Gate 0/1 (are the clusters real & reproducible across cohorts?) |
| A3 | **Antigen-resolution pipeline** TCR↔HLA↔peptide | `airrflow` + `hlatyping` + `epitopeprediction` + LC-MS | VDJdb, IEDB, HLA Ligand Atlas (target the DP/DQ gaps) | Enables gate-3 antigen-specific-tolerance design |
| A4 | **Isotype-stratification predictive framework** (FcRn vs BAFF/APRIL) | autoantibody_isotype_stratification | public MG serology | **Gate 3** (interaction-test design + power) |
| A5 | **Interaction-test harness** — a reusable module that, given a biomarker + a stratified trial design, computes the biomarker × treatment interaction + "% decisions changed" | scorecard + stats module | any | Gate 3/4 tooling, reusable across pilots |

**Implementation phasing**
- **Phase 1 (weeks 1–3):** A4 + A5 (isotype + interaction-test harness) — smallest, most gate-3-legible, directly tied to VorBio/argenx. Add the interaction-test + "% decisions changed" output to the isotype workflow report.
- **Phase 2 (weeks 3–8):** A1 + A2 (endotyping + reproducibility audit) — the flagship "harmonization/reproducibility" capability; produces both a demo and a manuscript (see §4, M1/M2).
- **Phase 3 (weeks 6–12):** A3 (antigen resolution) — the Adaptive-thesis lane; produces the antigen manuscript (M4).

### Track B — Client pilots (scoped, revenue-bearing)
| Account | Pilot | Gate framing | Ask |
|---|---|---|---|
| **VorBio / Sokolove** | Isotype stratification on their gMG Phase 3 screen-fails → telitacicept-addressable % + interaction-test design | Gate 3, predictive | Paid pilot; enrich Phase 3 |
| **argenx** | Seronegative-MG / CIDP responder stratification | Gate 3 | Paid pilot |
| **UCB / VanBaaren** | Multimodal target-discovery + endotyping (mirror her methodology, run on MG) | Capability/credibility | Co-development / lighthouse |
| **A tolerance developer (Repertoire-class)** | Antigen-resolution (TCR↔HLA↔peptide) for "which antigen, which patient" | Gate-3 enabler | Services relationship |

### Evaluation protocol (applies to every demo & pilot)
1. **Report gate level explicitly** — never present a gate-2 signature as stratification.
2. **Always report the two metrics the field hides:** biomarker × treatment **interaction** (CI + p), and **fraction of decisions changed**.
3. **Beat the cheap clinical baseline** (age, duration, ANA/anti-CCP, CRP, prior failed therapies) — report ΔAUC against it.
4. **Reproducibility first** — out-of-cohort label transfer + longitudinal stability before any biology claim.
5. **Every scoring choice citable** (as with the OT two-layer target scorecard).

---

## 4. Manuscripts to write quickly and put online

Goal: establish credibility + demonstrate the corrected capability breadth, all on **public data** (no biobank blocker), fast to draft because the workflows exist. Preprint on bioRxiv/medRxiv.

| ID | Title (working) | Thesis / why it lands | Data | BioMate capability shown | Effort |
|---|---|---|---|---|---|
| **M1** | *Reproducible multimodal endotyping of autoimmune disease with an orchestrated MOFA+ pipeline* | The field can't reproduce its own endotypes; here's a harmonized, reproducible pipeline with out-of-cohort validation | ImmPort/GEO/3TR-ADEx | MOFA+ integration + harmonization | Medium |
| **M2** | *How many SLE endotypes are there? A reproducibility audit of 3-, 5-, and 8-cluster schemes* | Provocative, high-visibility; re-derives published schemes on independent data and quantifies (in)stability — positions BioMate as the neutral reproducibility layer | public SLE multi-omics | integration + `cellmixs` + clustering | Medium (re-analysis) |
| **M3** | *Autoantibody-isotype composition as a predictive biomarker for FcRn vs BAFF/APRIL therapy: a gate-3 framework* | Formalizes the interaction-test design + power for the VorBio/argenx thesis; directly useful to a drug developer | public MG serology | isotype stratification + interaction-test harness | Low–Medium |
| **M4** | *An open TCR↔HLA↔peptide antigen-resolution pipeline targeting the HLA-DP/DQ immunopeptidome gap* | Attacks the exact bottleneck the field names; demonstrates the Adaptive-thesis lane on public data | VDJdb, IEDB, HLA Ligand Atlas | airrflow + hlatyping + epitopeprediction + LC-MS | Medium–High |
| **M5** | *Five gates for evaluating AI patient stratification* (Perspective) | Thought-leadership; formalizes the evaluation framework with PROFILE as the canonical failure; establishes BioMate as the rigor authority. No new compute | — | framework | Low |

**Sequencing:** M5 first (fastest, pure framework, sets the rigor narrative) → M3 (ties to live pilots) → M1/M2 (flagship reproducibility) → M4 (antigen moat). M2 and M5 are the highest visibility-per-effort.

**Guardrails for every manuscript**
- Report gate level; report interaction + decisions-changed; beat the cheap baseline; publish code/workflows (reproducibility is the moat — showing it is the marketing).
- Do NOT over-claim clinical utility (gate 4/5) from public retrospective data — frame as gate-0/1 reproducibility or gate-3 *design*, honestly.

---

## 4b. Internal / multimodal LLM plan — per-client adaptation

The engine already exists — this is **assembly, not greenfield**:
- **`backend/lib/galaxy/ai/ml_training/`** (colleague's work, on `origin/integration/next-phase`): Ludwig low-code training + **`ludwig_llm` LoRA/QLoRA fine-tuning**, declarative multimodal configs, MLflow tracking, BentoML serving, rule-first intent routing, executor→AWS Batch bridge. **Validated end-to-end**: chat → Batch → real LoRA fine-tune → LoRA adapter to S3. Flag-gated (`ML_TRAINING_ROUTING`).
- **`infra/vllm`**: vLLM serving + `sync-adapters.sh` — serves per-adapter, one base, many adapters.

### Core principle — one base cannot fit all; adapt per client
A shared base model + a **per-client LoRA/QLoRA adapter fine-tuned only on that client's internal data.** Rationale:
- **Data isolation / IP** — each adapter trains on one client's data, never pooled; matches the closed-system requirement (UCB) and the field's federated precedent (the 261-donor SLE tensor-decomposition without pooling cells). Where IRB forbids export, fine-tune client-side and share only adapter weights.
- **Domain adaptation** — their assays, nomenclature, endotype definitions, report house-style.
- **Cost** — vLLM multiplexes many client adapters over one base at serve time.

### Multimodal, not just text
Stratification evidence is multimodal (tabular omics, scRNA/CyTOF embeddings, serology, text). Ludwig is declaratively multimodal (tabular + text + sequence + image), so:
- **Predictive layer** — Ludwig multimodal models over a client's omics → endotype / biomarker / gate-3 predictions (the numbers).
- **Reasoning/report layer** — an LLM (per-client adapter) that reasons over the evidence + prioritisation panel and writes the gate-3 narrative (interaction test, % decisions changed) in the client's format.

### Build phases (each reuses existing infra)
| Phase | What | New vs existing | Data risk |
|---|---|---|---|
| **L1** | Per-client **RAG** — index client docs/cohort metadata; LLM answers + drafts reports grounded in their data | RAG layer over existing serving; no training | None (closed, nothing leaves) |
| **L2** | Per-client **LoRA fine-tune** on their instruction data (past stratification decisions, report style) → adapter served via vLLM | **Exists** (`ludwig_llm`); wire to the stratification use case | Their data in a closed Batch run |
| **L3** | **Multimodal** Ludwig model over their omics (endotype/biomarker) + LLM adapter narrates | Ludwig multimodal config (declarative) | Closed |
| **L4** | **Federated** fine-tune where export is forbidden — adapters trained client-side, only weights shared | Federated wrapper around L2 | None (data never leaves client) |

### Why this is a moat (not a commoditized public LLM)
The value is **per-client-adapted, closed, multimodal, gate-3-aware reasoning over the client's internal data** — not a generic model on public data. It compounds the reproducible-orchestration moat: BioMate runs the multimodal pipeline *and* ships a client-private model that speaks their data. Evaluated per-client on held-out client tasks, MLflow-tracked (already in the module), same gate discipline.

### Immediate step
Pull the two `ml_training` commits (`2d512aaf9`, `1094e00b7`) locally, then wire an L1 RAG + L2 `ludwig_llm` path to a stratification instruction set as the first per-client-adaptation demo (pairs with pilot Track B).

---

## 5. One-paragraph bottom line

The prior draft's rigor stands, but its premise was too narrow: BioMate is not an LC-MS antigen-ID tool, it is the **multimodal, reproducible, gate-3 stratification-orchestration layer** — and it already holds the antigen-resolution lane (airrflow + hlatyping + epitopeprediction + LC-MS) the draft treated as an aspiration. The play is unchanged in *shape* (sell capability to pharma development, not a per-test product) but far stronger in *scope*: harmonized multimodal endotyping + antigen resolution + gate-3 interaction-testing, proven on public data through a fast preprint pipeline (M5→M3→M1/M2→M4) and monetized through scoped pilots (VorBio, argenx, UCB, a tolerance developer). The reproducibility and breadth *are* the moat against the "commoditized by public data" objection.
