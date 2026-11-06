# Immune-Mediated Multi-Omics — Blog Series Plan

**Date:** 2026-10-08
**Format:** a series of dedicated blog pages on the public site (webpage_design_v2), styled like the
existing `blog-*.html` posts, grouped under a Newsroom / collection view.
**Voice:** [[feedback_formal_tone]] — educational, professional, capability-framed.
**Confidentiality:** [[feedback_website_no_internal_work]] — public literature, public datasets, and
BioMate *capabilities* only. No internal targets, methods, pilot results, or program specifics.
**Sources:** draws on the three living surveys ([[project...]] via `20261008_LIVING_REFERENCES_INDEX.md`).

## Proposed series (each = one page)

1. **Why multi-omics for immune-mediated disorders** — the problem: heterogeneity, responder
   variability, tissue access; why one modality isn't enough. (framing)
2. **The public multi-omics data landscape** — tour of the datasets catalog (what exists, scales,
   access), what's rich vs study-poor for autoimmune.
3. **Three ways to integrate multi-omics — and when to use each** — linear/traditional vs
   knowledge-graph/data-driven vs virtual-cell/LLM; the tasks each is best at; how they complement.
4. **Responder stratification: the clinical white space** — what the field can/can't do today
   (educational, non-confidential).
5. **From multi-omics target to a candidate** — the end-to-end arc (target → design → de-risk →
   translate), as a *capability* walkthrough. Mirrors the homepage drug-discovery band.
6. **Per-disorder deep dives** (one page each, as the per-disorder survey matures): RA · SLE · MS ·
   IBD · SSc · T1D · others — datasets, approaches, current ability.
7. **All-atom design for peptides & macrocycles** — approaches + datasets survey, public-facing.
8. **Keeping integration honest — QC for multi-omics** — over-correction / erased-biology failure
   modes and how QC guards against them (educational).

## Sequencing
Publish 1–3 first (framing + landscape + methods) once the surveys are compiled; per-disorder (6)
and all-atom (7) follow as those surveys fill in. Each post links to the next and to a collection
landing (grouped in Newsroom).

## Drafts (publication-ready prose — public/educational, no internal work)

> Source: the three living surveys. Capability-framed; "BioMate" appears only at platform-capability
> level. Ready to drop into the blog template (`blog-*.html`).

### Post 1 — Why Multi-Omics for Immune-Mediated Disorders

Immune-mediated diseases look like single diagnoses but behave like populations of distinct
molecular diseases. Two patients who both carry a diagnosis of rheumatoid arthritis, lupus, or
inflammatory bowel disease can have inflammation driven by entirely different cell types, cytokine
circuits, and genetic risk — which is why a drug that transforms one patient does little for the
next. The central problem of the field is not describing *that* these diseases are heterogeneous;
it is resolving *which* axis of heterogeneity matters for a given patient and a given therapy.

No single measurement captures that. Genetics tells you the inherited risk but not the current
state of the tissue. Bulk transcriptomics averages over the very cell types whose balance defines
the disease. Protein abundance — the layer closest to drug action — correlates only modestly with
mRNA (on the order of r ≈ 0.4 in many tissues), so a transcript-only readout misses most of the
biology a therapeutic will actually engage. Each layer is a projection; the disease lives in their
intersection.

Multi-omics integration is the discipline of reconstructing that intersection. The modern playbook
is consistent across disorders: genome-wide association studies map inherited risk; functional
genomics (expression QTLs, single-cell chromatin accessibility, colocalization) converts
non-coding risk loci into the specific genes and cell types that carry them; single-cell and
spatial transcriptomics identify the pathogenic cell states in the affected tissue; and bulk
molecular profiling stratifies patients for treatment-response prediction. Together these turn a
clinical label into a mechanistic, cell-resolved, patient-specific picture.

The payoff is tangible where the data are rich. In inflammatory bowel disease, cellular modules
identified by single-cell analysis of mucosa are associated with resistance to anti-TNF therapy. In
psoriasis, convergent genetic, transcriptomic, and functional evidence pinned the IL-23/IL-17 axis —
and that convergence translated directly into a generation of successful biologics. These are
proofs that integrated multi-omics is not description for its own sake; done well, it nominates
targets and stratifies patients.

A platform that carries a scientist from raw multi-omics data to an integrated, quality-checked,
interpretable result — without a bioinformatics team per project — is what makes this routine rather
than heroic. The rest of this series walks through the public data that makes it possible, the
methods that integrate it, and where the field can and cannot yet deliver, disorder by disorder.

### Post 2 — The Public Multi-Omics Data Landscape

A multi-omics program is only as good as the data it can reach, and for immune-mediated disease the
public landscape is richer — and more uneven — than most researchers assume. [Summarize the dataset
catalog: cancer references (TCGA, CPTAC, ICGC/PCAWG, HTAN) as method-development backbones; immune
cohorts (ImmPort >58,000 subjects; TEDDY's 15-year T1D birth cohort; DICE and OneK1K immune-cell
eQTL maps; the CLL MOFA reference); the single-cell/spatial atlases (Human Cell Atlas ~62M cells,
CZ CELLxGENE Census ~217M, HuBMAP); and population multi-omics (UK Biobank genome+proteome+
metabolome at ~500k, GTEx, Open Targets). Then the honest asymmetry: RA, SLE, IBD, MS, T1D,
psoriasis and AD have cell-resolution atlases and consortium infrastructure (AMP, IMSGC, IIBDGC),
while SSc, Sjögren's, MG, CIDP and AS remain single-institution and study-poor. Close with how to
access: GEO/ArrayExpress for open data, EGA/dbGaP for controlled, and the role of standardized
portals (CELLxGENE Census API) in making cross-dataset integration practical.] — full prose to be
expanded from `20261008_MULTIOMICS_PUBLIC_DATASETS.md`.

### Post 3 — Three Ways to Integrate Multi-Omics, and When to Use Each

There is no single best integration method — there are three families, each strongest at a
different job. **Linear/traditional** methods (MOFA, iCluster, SNF, DIABLO) assume the shared signal
lives in a low-dimensional subspace; they are interpretable and sample-efficient, which makes them
the right default for bulk cohorts, factor/driver discovery, subtyping, and sparse biomarker panels.
**Knowledge- and graph-based** methods (GLUE, PrimeKG/TxGNN, PARADIGM) inject known biology —
regulatory links, pathways, knowledge graphs — so they excel when the modalities don't share a
feature space and when you need mechanism, not just correlation, and they power knowledge-driven
drug repurposing. **Foundation-model / "virtual cell"** approaches (scGPT, Geneformer, UCE, the Arc
Institute's State model, perturbation models like GEARS) pretrain on hundreds of millions of cells
and shine at atlas-scale single-cell integration and at predicting responses to unseen perturbations.

The categories complement rather than compete. A realistic workflow chains them: linear methods
discover factors, subtypes, and candidate biomarkers from a cohort; knowledge graphs anchor those
signals to pathways and nominate targets; foundation models simulate perturbations in silico to
prioritize experiments — and the results loop back to refine the priors. Knowledge even flows *into*
the learned models (GEARS uses a gene–gene graph; GLUE a regulatory prior), improving data
efficiency. One discipline matters throughout: foundation-model advantages are real but not
automatic — independent benchmarks show that in zero-shot settings they can trail simple baselines,
so the robust practice is to treat a transparent linear method as the bar every fancier model must
clear on the specific task. [Expand with the task-fit table from
`20261008_MULTIOMICS_INTEGRATION_SURVEY.md`.]

---

## Update log
- **2026-10-08** — Plan created; survey compilation done (4 passes). Drafted Post 1 (full), Posts 2–3
  (lead prose + expansion notes). Next: render Post 1 to the blog template as a preview; expand 2–3.
</content>
