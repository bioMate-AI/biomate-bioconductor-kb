# From Paper to Pipeline: Retrieval-Grounded Synthesis of Executable Bioinformatics Workflows from the Published Methods Literature

**Authors:** BioMate Team (author list TBD)
**Target venue:** *Bioinformatics* (Application Note / Original Paper) — primary; *GigaScience* (Technical Note) — secondary.
**Status:** Draft — 2026-07-14. Preliminary tool-locator benchmark reported; end-to-end reproduction protocol defined, runs pending.

---

## Abstract

Reproducing a published bioinformatics analysis requires translating a paper's Methods section into an executable pipeline — a manual, error-prone task that gates reproducibility and slows re-analysis. The 2025–2026 wave of "paper-to-code" systems (DeepCode, Paper2Code, AI-Scientist) automates this for machine-learning papers but emits Python training scripts; **none target biology or emit executable pipeline languages** (Nextflow, Snakemake, Galaxy, CWL), and a direct search of the open-source landscape returns zero paper-to-workflow tools for the life sciences. We present the design and a first evaluation of a **paper-to-workflow module** that converts a paper's methods into a runnable Nextflow/nf-core pipeline by *retrieving and composing* over a curated catalog of 2,455 executable workflows rather than synthesizing code from scratch — trading unconstrained generation for reproducibility and provenance. The module has five stages (paper-fetcher → methods-extractor → tool-locator → wrapper-generator → chain-composer) built on production BioMate components: full-text methods extraction, hybrid BM25+dense retrieval, a search-first workflow generator, and a shadow-deployed chain composer. We isolate and evaluate the **tool-locator** stage on a curated benchmark of paper→known-pipeline pairs, where methods-style queries route to the correct catalog pipeline with Hit@5 = 1.00, Hit@3 = 0.71, Hit@1 = 0.43, MRR = 0.63 using lexical retrieval alone (a lower bound; production adds dense retrieval and LLM re-ranking). We demonstrate the ingestion loop end-to-end on two real academic collaborations — Dr. Degui Zhi's TorchGWAS/UDIP and Folding-Docking-Affinity pipelines, and Dr. Zhao's disease-state-resolved GWAS cell-type attribution — each hand-ported today into an executable BioMate chain, i.e. the exact task the module automates. We define an end-to-end reproduction benchmark (methods-extraction slot-F1, parameter-fill accuracy, and QC-gated reproduction rate on public data) as the field's missing evaluation. Every ingested paper additionally deposits new workflows, chains, and benchmark cases back into the platform catalog, making paper ingestion a mechanism for continuous capability growth.

---

## 1. Introduction

### 1.1 The reproducibility translation gap

A published bioinformatics result is only reproducible to the extent that a reader can reconstruct its pipeline. In practice the Methods section is prose: "reads were aligned with STAR 2.7.9a to GRCh38, quantified with Salmon, and differential expression tested with DESeq2 at FDR < 0.05." Turning that sentence into a runnable pipeline — choosing the aligner module, wiring the quantifier, setting the FDR threshold, provisioning references and containers — is manual work that can take hours to days and is a well-documented source of irreproducibility. The task recurs every time a lab wants to re-analyze published data, benchmark against a prior method, or apply a paper's protocol to new samples.

### 1.2 Paper-to-code exists — for the wrong output language and the wrong field

The 2025–2026 "paper-to-code" literature is substantial but narrow. DeepCode (15.9k★), going-doer/Paper2Code (4.7k★, the reference implementation of the *Paper2Code* method), and Sakana AI's AI-Scientist / AI-Scientist-v2 (14.1k / 6.7k★) all read an ML paper and emit a Python/PyTorch repository; AI-Scientist-v2 adds agentic tree-search over code variants. These target ML/CS papers and produce arbitrary training code. For a biology audience the requirement is different: not novel scripts but **reproducible pipeline runs** in a workflow language (Nextflow DSL2 / nf-core), executable on batch infrastructure with provenance. A direct survey (Section 2) finds **no open-source project** that converts a paper to a bioinformatics workflow — `gh search repos "paper to nextflow OR snakemake OR galaxy"` returns zero results, and the nf-core, Galaxy, and Snakemake communities publish only hand-authored tutorials.

### 1.3 Synthesis-from-scratch is the wrong default for biology

The ML paper-to-code systems synthesize code freely because ML methods are often novel. Bioinformatics is different: the overwhelming majority of published analyses reuse a small number of canonical pipelines (nf-core/rnaseq, nf-core/sarek, DESeq2, MACS2, Scanpy, QIIME2). For this audience, **retrieval-and-composition over a curated executable catalog is strictly preferable to free synthesis** — it yields runs that are reproducible, containerized, and traceable, and it fails safe (an unmatched method surfaces as "no pipeline found" rather than as plausible-but-wrong generated code). Free synthesis is the fallback for genuine gaps, not the default.

### 1.4 Contributions

1. A **five-stage paper-to-workflow architecture** (paper-fetcher → methods-extractor → tool-locator → wrapper-generator → chain-composer) that is retrieval-first over a 2,455-workflow catalog, built on production components rather than a greenfield agent.
2. A survey establishing that **no drop-in upstream exists** for bio paper-to-workflow, and a per-stage map of what to reuse from the ML paper-to-code ecosystem (Section 2).
3. A **curated tool-locator benchmark** — paper-methods query → known catalog pipeline — with a reproducible harness and a first (lexical, lower-bound) result: Hit@5 = 1.00, MRR = 0.63 (Section 5).
4. Two **real end-to-end use cases** (Zhi lab; Zhao lab) where a lab's published methods are ported into executable BioMate chains, demonstrating the ingestion target and the knowledge-feedback loop (Section 6).
5. A **proposed reproduction benchmark** (extraction slot-F1 → parameter-fill → QC-gated reproduction on public data) that the field currently lacks (Section 7).

---

## 2. Related work and the open-source landscape

We surveyed the paper-to-code ecosystem in June 2026 (full survey: `docs/20260629_PAPER_TO_CODE_OSS_SURVEY.md`).

**Paper-to-code for ML.** *Paper2Code* (going-doer/Paper2Code, 4.7k★) formalizes a three-stage plan → analyze → code pipeline producing a runnable repository from an ML paper; its planner emits a structured "plan.json" intermediate that is the cleanest reusable idea for our methods-extractor. *DeepCode* (HKUDS, 15.9k★) is a multi-agent Paper2Code/Text2Web/Text2Backend system whose coder agent + file-tree planner are a reference for constrained synthesis. *AI-Scientist* / *AI-Scientist-v2* (Sakana AI, 14.1k / 6.7k★, Apache-2.0) run idea→code→experiment→write loops; v2's tree-search over code variants is the design analog to our QC-gate auto-loop.

**Bio agents without paper ingestion.** *Biomni* (snap-stanford, 3.3k★) is a biomedical agent with a curated tool registry and skill catalog; it routes intents to bio tools but does not ingest papers — its registry schema is the strongest reference for our tool-locator. *ToolUniverse* (mims-harvard, 1.5k★) is a complementary large tool registry.

**The gap.** No high-star, actively maintained project targets biology workflows or emits Nextflow/Snakemake/Galaxy/CWL. Our per-stage reuse strategy is therefore *architecture reuse, not code reuse*: fork Paper2Code's planner decomposition, mirror Biomni's registry schema, constrain a DeepCode-style coder to nf-core module conventions, and borrow AI-Scientist-v2's tree-search for the auto-loop — while building the fetcher and bio-vocabulary extractor in-house.

**Benchmarks we position against.** TaskBench (arXiv:2311.18529; GPT-4 ≈ 65% tool-F1), the Berkeley Function-Calling Leaderboard (BFCL), LAB-Bench ProtocolQA, and Galaxy Workflow Retrieval (arXiv:2511.01757). None evaluates paper→executable-workflow over a specialist bioinformatics catalog.

---

## 3. System design

### 3.1 Pipeline overview

```
paper-fetcher → methods-extractor → tool-locator → wrapper-generator → chain-composer → QC auto-loop
   (exists)        (partial)          (exists)         (exists)         (prototype)       (production)
```

The module is retrieval-first: the tool-locator and wrapper-generator attempt to *match* the extracted methods to existing catalog workflows before any free synthesis. Synthesis is gated behind a confidence threshold.

### 3.2 Stage details and their production substrates

**paper-fetcher.** Reuses BioMate's `research_agent.py` fetch primitives: Semantic Scholar search, PMC full-text via BioC-JSON + E-utils, Europe PMC PDF resolution, PyMuPDF page rendering, and HTML figure-caption fallback (unit-tested in `test_paper_extraction.py`). These primitives today feed a research Q&A/citation agent; the module re-targets them at workflow synthesis. Supported sources: CORE, arXiv, PubMed/PMC, bioRxiv, Europe PMC.

**methods-extractor.** Extracts the Methods/Results text (`_fetch_pmc_fulltext`) and — the piece to be built — distills it into a typed `methods.json` intermediate representation: assay type, organism/genome build, tools + versions, key parameters (FDR, aligner, thresholds), inputs, and QC gates. Following Paper2Code, this typed IR is the contract between extraction and composition; without it, prompt drift compounds across stages.

**tool-locator.** Matches the methods IR against the 2,455-workflow catalog using BioMate's production hybrid search — BM25/FTS + BGE dense retrieval + entity-boost, with a type-flow graph that chains workflows by matching typed outputs→inputs (e.g. `counts_matrix` → a consumer). This is the stage we benchmark in Section 5.

**wrapper-generator.** For a matched pipeline, prefills parameters; for a partial match, adapts a template; for a genuine gap, synthesizes a `subworkflows/<name>/main.nf` + params schema via the production `NextflowComposer` stack (L0 subworkflow cache → L1 FTS tool retrieval → L2 DB-only tool-plan validation → L3 single-LLM DSL2 emission → L4 syntax validation). Confidence tiers mirror `generate_workflow_unified`: > 0.8 reuse, 0.5–0.8 adapt, < 0.5 synthesize under tool constraint.

**chain-composer.** For multi-step protocols, composes an ordered chain of catalog workflows. BioMate's `chain_composer` prototype does this from a natural-language query today: NER → pattern retrieval (BM25 over a canonical pattern library) → curated-chain exemplar retrieval → candidate-workflow retrieval with type-flow traversal → LLM compose → verifier (flags unknown workflows, self-loops, cycles, orphan steps) → confidence-scored surfacing mode (`upfront`/`stepwise`/`reactive`). It is **shadow-deployed** on production traffic (`BIOMATE_COMPOSER_SHADOW=1`, default off, log-only, rate-limited) to collect telemetry without exposing output — the harness we extend to accept a methods IR instead of a query string.

**QC auto-loop.** Every ingested pipeline runs through the same QC-gate + remediation loop as user-authored workflows (try → measure → remediate → retry), so paper methods are validated, not trusted as ground truth.

### 3.3 Design invariants

- **Retrieval before synthesis.** Free code generation is the last resort, not the default.
- **Typed IR as the inter-stage contract.** All stages read/write `methods.json`.
- **Fail-safe.** An unmatched, low-confidence method surfaces as "no pipeline found," never as unverified generated code presented as correct.
- **Provenance.** Each ingested workflow records the source paper (DOI/accession) and the tool versions extracted.

---

## 4. Benchmark methodology

### 4.1 Why isolate the tool-locator first

The end-to-end task (paper → reproduced result) has many failure points; a single aggregate number would be uninterpretable. We therefore evaluate stages independently, starting with the **tool-locator**, which is the load-bearing retrieval step and is already fully implemented in production. This yields an honest, reproducible measurement today, and defines the harness the other stages plug into.

### 4.2 Dataset

We curated paper→pipeline pairs where a published analysis maps to a canonical pipeline present in the catalog. Each pair carries a **methods-style query** (a distilled Methods-section description, standing in for the methods-extractor's output) and a set of acceptable target patterns. Pairs whose target is absent from the catalog snapshot are dropped and reported. The dataset (`benchmark/pairs.json`) spans 14 scorable pairs across RNA-seq (bulk DE, paired/single-end quantification, visualization), single-cell (Scanpy clustering, edgeR pseudobulk), epigenomics (ChIP-seq/MACS2, ATAC-seq, CUT&RUN), 3D genome (Hi-C), metagenomics (MAGs), somatic variant calling (Manta), CRISPR editing, and clinical metaproteomics.

### 4.3 Retrieval and metrics

Retrieval uses BioMate's production BM25 scoring primitives (`chain_composer.retrieval._BM25Index`, `_tokenize_bm25`, `_expand`) over the catalog fields (name + domain + description + tools + annotation). We report Hit@1, Hit@3, Hit@5, and MRR (mean reciprocal rank of the first correct hit) at top-k = 5. The harness (`benchmark/run_tool_locator_bench.py`) is deterministic and offline.

**Honest scope.** The evaluated configuration is **lexical retrieval only**, over a 967-workflow local catalog snapshot lacking the `annotation_v2` enrichment column present on the production 2,455-workflow catalog. Production additionally applies BGE dense retrieval and (optionally) LLM re-ranking. Reported numbers are therefore a **lower bound** on the deployed system; we state this explicitly rather than reporting the stronger stack we did not run here.

---

## 5. Results

### 5.1 Tool-locator retrieval

| Metric | Value |
|---|---|
| Pairs scored | 14 |
| Pairs dropped (target absent) | 0 |
| **Hit@1** | **0.429** |
| **Hit@3** | **0.714** |
| **Hit@5** | **1.000** |
| **MRR** | **0.631** |

Every paper's correct pipeline appears within the top 5 (Hit@5 = 1.00), and the first correct hit is at rank 1 or 2 for 9/14 pairs. The lexical-only configuration's weaknesses are exactly where semantic retrieval helps: `rnaseq_quant_pe` (rank 4 — "paired-end quantification" lexically collides with differential-expression pipelines), `atacseq` (rank 4 — a `biomni` differential-accessibility tool outranks the canonical ATAC pipeline), and `mag_metagenomics` (rank 4 — a binning sub-workflow outranks the full MAG pipeline). These are precisely the near-synonym and part-vs-whole confusions that BGE dense retrieval and type-flow composition are designed to resolve, supporting the claim that the deployed stack exceeds this lower bound.

### 5.2 Interpretation against existing benchmarks

The production **routing** benchmark (natural-language query → correct workflow) scores 94.6% (±2.1%) and routing-IR reports MRR = 0.847, P@1 = 0.742. Our paper-methods queries are longer and noisier than user queries, so the drop to MRR = 0.63 (lexical-only) quantifies the added difficulty of routing from paper prose rather than a clean intent — the core scientific claim of the tool-locator evaluation. The **param_prefill** benchmark (the analog of extracting parameter values from methods) is currently non-functional (all-zero, a known runner bug) and must be repaired before the parameter-fill stage can be scored.

---

## 6. End-to-end use cases: lab methods → executable BioMate chains

Two active academic collaborations demonstrate the ingestion target. In both, a lab's *published methods* are today ported **by hand** into executable BioMate workflows and chains — the exact manual task the module automates — and each deposits new capability into the platform catalog.

### 6.1 Dr. Degui Zhi lab (UTHealth) — population-scale GWAS and protein-ligand affinity

Grounded in the lab's recent papers, `backend/scripts/add_zhi_lab_chains.py` inserts two executable pipelines into `galaxy_ai_tools.db`:

- **TorchGWAS UDIP phenotype scan** (`torchgwas_udip_phenotype_scan`, domain `population_genetics`) — a 4-phase pipeline (phenotype QC → kernel + stratify → GPU TorchGWAS scan → loci report) wrapping the lab's GPU-accelerated GWAS tool (github.com/ZhiGroup/TorchGWAS, MIT) over UDIP-derived brain-image phenotypes.
- **Folding-Docking-Affinity (FDA) screen** (`fda_protein_ligand_affinity`, domain `drug_discovery`) — a 4-phase pipeline (ESMFold target → library docking → FDA affinity head → ranked report with uncertainty) wrapping github.com/ZhiGroup/FDA.

These build toward an **autoimmune GWAS target-prioritization chain** (TorchGWAS → RaPID ancestry stratification → coloc/SMR with DICE immune eQTLs → GNN target ranking over ChEMBL/Open Targets), with a pre-registered validation benchmark: recover known validated RA targets (JAK1/2, IL-6R, CD20, TYK2, PTPN22) in the top decile using published UK Biobank + FinnGen RA GWAS (N = 933,649). The clinical-LLM workstream (Med-BERT-backed trial-design reasoning) is a downstream Layer-3 consumer. Full proposal: `docs/20260701_PROPOSAL_ZHI_COLLABORATION.md`.

### 6.2 Dr. Zhao lab (UTHealth) — disease-state-resolved GWAS cell-type attribution

`backend/scripts/add_zhao_lab_chains.py` ports the lab's method — extending scGWAS with a disease-activity-aware single-cell foundation model — into a BioMate chain. The scientific advance is resolving GWAS loci to *cell type × disease-activity state* (e.g. "PTPN22 → IFN-high Treg in SLE flare, absent in IFN-low remission Treg") by training an IFN-spectrum multi-disease encoder (two-head objective over disease type + IFN activation) and substituting its embeddings for scGWAS's static atlas. This is a paper-methods → executable-chain ingestion whose output is a new, benchmarkable capability. Full proposal: `docs/20260706_ZHAO_COLLABORATION_PROPOSAL.md`.

### 6.3 Knowledge feedback into the platform

Both cases illustrate the module's second function: **every ingested paper grows the catalog.** Ported pipelines land as new `workflows` rows and `workflow_chains` entries (e.g. `add_gwas_methods_chain.py`); their validation criteria become new benchmark cases (RA-target recovery; disease-state attribution); and their tool wrappers become reusable across future queries. Paper ingestion is thus not a one-shot converter but a **continuous capability-acquisition loop** — the same loop the Auto-Update module runs for GitHub tools (companion manuscript), here driven by the methods literature.

---

## 7. Proposed end-to-end evaluation (the field's missing benchmark)

No published benchmark evaluates paper→executable-workflow over a specialist bioinformatics catalog. We propose a three-tier protocol, each tier a strict prerequisite for the next:

1. **Methods-extraction slot-F1.** Score the typed `methods.json` against a human-annotated gold spec (tools, versions, genome build, key thresholds, assay type). Field-level precision/recall, BFCL-style. Substrate exists (`_fetch_pmc_fulltext`); the IR does not yet.
2. **Parameter-fill accuracy.** Given the extracted methods, does the module fill workflow parameters matching the paper's stated values? Exact-match for enums, tolerance for numerics. Requires repairing the param_prefill runner.
3. **QC-gated reproduction rate.** For pairs whose data is public (URL-Import-able: SRA/GEO/ENA/PRIDE/MetaboLights/EMPIAR), run the routed pipeline through the QC auto-loop and measure (a) execution-to-completion, (b) QC-gate pass, (c) reproduction of the paper's headline number within tolerance. This is the strongest and novel metric.

We additionally include **confusable-pair robustness** (sarek vs. variantcalling vs. dualrnaseq for "somatic variant calling") to test discrimination, and we will scale the curated pair set to 50–100 pairs with public data.

---

## 8. Limitations

- **End-to-end is not yet wired.** Paper-fetch and methods-extraction primitives exist but feed a research Q&A agent; the tool-locator and wrapper-generator are query-driven in production; the chain-composer is shadow-only. The paper→workflow path is assembled from these parts but not yet a single production route.
- **Tool-locator result is a lower bound.** Lexical-only, 967-workflow snapshot, no dense retrieval or LLM re-rank; 14 pairs. The number establishes a floor and a harness, not the deployed ceiling.
- **Curated queries stand in for real extraction.** Section 5 uses hand-distilled methods queries; the true difficulty includes extraction error, which tier-1 of Section 7 will measure.
- **Reproduction not yet run.** Section 7 is a protocol, not results.

---

## 9. Conclusion

Bioinformatics needs paper-to-*pipeline*, not paper-to-code: reproducible, containerized, catalog-grounded workflows rather than free-synthesized scripts. We presented a retrieval-first, five-stage module built on production BioMate components, established that no upstream exists, and reported a first honest measurement of its load-bearing retrieval stage (Hit@5 = 1.00, MRR = 0.63, lexical lower bound). Two real lab collaborations show the ingestion target and the knowledge-feedback loop by which every paper grows the platform. The end-to-end reproduction benchmark we define is, to our knowledge, the first for paper→executable-workflow over a specialist catalog, and is the natural next milestone.

---

## Reproducibility

- Benchmark harness + dataset: `research_repos/biomate_paper2workflow_paper/benchmark/`
- Results: `research_repos/biomate_paper2workflow_paper/results/tool_locator_results.json`
- OSS survey: `docs/20260629_PAPER_TO_CODE_OSS_SURVEY.md`
- Data sources / URL import: `docs/20260629_DATA_SOURCES_AND_URL_IMPORT.md`
- Lab chains: `backend/scripts/add_zhi_lab_chains.py`, `add_zhao_lab_chains.py`, `add_gwas_methods_chain.py`
- Chain composer: `backend/lib/galaxy/ai/chain_composer/`
