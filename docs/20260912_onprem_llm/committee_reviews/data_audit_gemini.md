### Executive Summary & Verdict

The rebuilt `data_pool_v2` exhibits **severe structural misalignment** across its three sources. While framed as a multi-source distillation to reduce templated generation, it conflates three distinct label spaces:
1. **Unconstrained concept tokens** from open-domain LLMs.
2. **Arbitrary unique database keys** from internal schemas.
3. **Repository/web-app maintenance artifacts** masquerading as workflow engineering.

Training on this raw pool will produce a model that hallucinates natural language concepts when tool slugs are required, emits broken schema arguments, suggests web-UI route patches for crashing bio-pipelines, and suffers from catastrophic eval leakage.

---

### 1. Committee Distillation: Root Cause, Salvageability, and Protocol

#### Root Cause: Labeling-Context Bug vs. Quality
This is **90% a labeling-context (RAG) bug** and **10% an evaluation bug**, not an intrinsic teacher-reasoning failure.
* **Bioinformatics Reality:** A user asking to *"run gene set enrichment on my ranked gene list"* is correctly served by GSEA. The teacher outputs `Gene Set Enrichment Analysis (GSEA)`. Expecting it to emit `clusterprofiler_gene_set_enrichment_analysis` zero-shot without catalog visibility requires psychic knowledge of the internal slug naming convention. 
* **ML Eval Reality:** The 0.27 DB agreement score measures **string-token collision**, not semantic or functional correctness. When prompted unconstrained, LLMs default to their highest-prior pre-training tokens (e.g., Broad Institute's GSEA, PCA, CMap).

#### Usability of Current Outputs
* **UNUSABLE (Drop Immediately as targets):** 
  * *Routing & Workflow Gen:* Cannot be used as direct generation targets. Training on these will cause BioMate to emit free-form strings rather than executable tool catalog handles.
  * *Param Extraction:* Fatal. The sample demonstrates the teacher emitting arbitrary YAML/Markdown (`analysis_method: Wilcoxon`, `ontology: Gene Ontology`) while the execution engine expects explicit BioConductor/R argument dictionaries (`{"organismDb": "Homo.sapiens"}`).
* **REPURPOSABLE (Immediate salvage):**
  * *Query Paraphrase Augmentation:* Invert the routing data. The teacher's concept-level outputs are high-value *user queries*. Map teacher concepts $\rightarrow$ DB gold slug to train the router on diverse user vernacular (e.g., mapping `"Run Connectivity Map Analysis"` $\rightarrow$ `signaturesearch`).
  * *Autofix Taxonomy Normalization:* The consensus categories (`Missing Input`, `Dependency`) can bootstrap a fixed 12-class categorical classifier for error triage, but **cannot** serve as direct code-fix patches.

#### The Correct Distillation Protocol
Teachers must run under the **exact inference architecture** intended for BioMate:
1. **Candidate-Constrained Routing:** Feed the user query into a bi-encoder dense retriever over the 4,200 workflows. Pass the Top-$K$ ($K=20$) catalog items (slug, description, expected inputs) to the teacher. Force the teacher to select from the candidate list or emit `NO_MATCH`.
2. **JSON-Schema-Constrained Param Extraction:** Supply the exact Pydantic/JSON Schema of the resolved workflow. Force structured outputs (e.g., JSON Schema constrained decoding) ensuring keys match internal parameter names (e.g., `organismDb`, `minGSSize`, `pvalueCutoff`).

---

### 2. Gold Validity: Routing Equivalence & Param Schemas

#### Routing: The "Single DB Slug" Fallacy
Enforcing a single DB slug as the unique gold label is **biologically and computationally invalid**.

```
Query: "run gene set enrichment on my ranked gene list"
├── clusterprofiler_gene_set_enrichment_analysis  [VALID: standard R/Bioc path]
├── fgsea                                         [VALID: faster preranked implementation]
├── broad_gsea_preranked_cli                      [VALID: canonical Broad Java desktop/CLI]
└── topgo_enrichment                              [INVALID: over-representation, not preranked GSEA]
```

* **The Problem:** Penalizing the model for selecting `fgsea` when the database anchor happens to point to `clusterprofiler` injects massive gradient noise and suppresses functionally equivalent or superior pipelines.
* **The Solution — Functional Equivalence Classes (Accept-Sets):**
  1. Cluster the 4,200 catalog workflows into **Equivalence Partitions** defined by `(Input_Types, Core_Mathematical_Operation, Output_Types)`.
  2. Each query $q$ maps to an **Accept-Set** $\mathcal{A}(q) = \{s_1, s_2, \dots, s_n\}$.
  3. **Scoring:** 
     $$\text{Precision@1} = \mathbb{I}(\hat{y} \in \mathcal{A}(q))$$
     For training, use multi-label cross-entropy over the candidate set, or sample uniformly from $\mathcal{A}(q)$ across epochs.

#### Parameters: Schema-Key Enforcement vs. Conceptual Extraction
* **The Problem:** The DB gold `{"organismDb": "Homo.sapiens"}` vs teacher output `ontology: Gene Ontology` illustrates a schema disconnect.
* **The Solution:**
  1. Define parameter types strictly: **System Execution Parameters** (threads, memory), **Biological Entities** (Taxon, Genome Build, Gene ID type), and **Algorithm Hyperparameters** (FDR thresholds, dispersion methods).
  2. The gold standard for parameter extraction **must be a valid JSON instance conforming to the target workflow's JSON Schema**.
  3. Natural language parameter extraction is only evaluated on its mapping to canonical controlled vocabularies (e.g., `Homo sapiens` $\rightarrow$ NCBI Taxonomy ID `9606` or BioConductor annotation pack `org.Hs.eg.db` / `Homo.sapiens`).

---

### 3. Self-Mining: Docs QA and Commit Fix Audit

The self-mining pool exhibits **critical domain and task mismatch**.

#### The Docs QA Risk
* **Sample Analysis:** `Q: "how many workflows implement params.mock_mode?" A: "Only 1 ... 23 have required-inputs"`.
* **Adversarial Audit:** This is **codebase-inventory meta-QA**, not bioinformatics workflow execution. It conditions BioMate to answer internal DevOps/CI questions rather than assisting bioinformaticians with pipeline configuration. 
* **Decision:** **QUARANTINE.** Unless the deployment specification explicitly includes a "Platform Admin / Developer Assistant" role, these samples degrade user-facing assistant performance.

#### The Commit Fix Risk
* **Sample Analysis:** `problem: "Export-to-CRO button does nothing" fix: "wire button to existing GET /api/drug-discovery/:id/export endpoint"`.
* **Adversarial Audit:** **Disastrous.** This is Web/React/REST API plumbing. If mixed into the autofix dataset, the model will suggest web API route patches when a Nextflow pipeline fails with an OOM killer or a DESeq2 script encounters non-converging dispersion estimates.
* **Decision:** **PURGE IMMEDIATELY.** 

#### Mandatory Self-Mining Ingestion Filter
To be included in `data_pool_v2`, commits and docs must pass a **Domain & Execution Boundary Filter**:
1. **File Extension Whitelist:** Changes must touch execution code: `*.nf`, `*.wdl`, `*.smk`, `*.cwl`, `*.sh`, `*.R`, `*.py`. Eliminate all changes touching `*.tsx`, `*.jsx`, `*.vue`, `*.css`, or API controllers.
2. **Error Pattern Whitelist:** The commit message or incident log must resolve execution-plane errors: exit codes (e.g., `137`, `1`), runtime exceptions (e.g., `Missing Chromosome Identifier in BAM`, `DESeq convergence failure`), or tool syntax deprecations.

---

### 4. Graph Anchors: Integrity of Deterministic Gold

Deterministic DB records are frequently assumed to be pristine; in production catalogs, they are often brittle.

```
Graph Anchor: workflow="a4"
Decompose Steps: ["Add gene annotation", "Unsupervised exploration", "Filter genes by variance", "Detect differential expression"]
```

#### Vulnerabilities in DB Metadata
1. **UI Display Labels $\neq$ Computational Nodes:** The sample `["Add gene annotation", ...]` uses descriptive marketing/UI labels. Does step 1 map to `biomaRt`, `org.Hs.eg.db`, or a custom AWK script? If the gold decomposition is just high-level prose, BioMate will generate plans it cannot compile into execution graphs.
2. **Stale/Static Defaults in DB Params:** DB parameter defaults frequently contain dummy constants (`threads: 1`, `outdir: "./results"`, `sample_sheet: "/path/to/test.csv"`). Training directly on these creates a model that ignores user context and defaults to hardcoded test paths.
3. **Subworkflow Granularity Inconsistency:** Workflow `a4` may embed a 10-tool subworkflow (e.g., GATK Best Practices) as a single step ("Call Variants"), while workflow `b12` exposes every step down to `samtools index`. 

#### Validation Protocol
* **Run a DAG Compilation Test:** Every graph anchor in `wfgen` and `decompose` must compile to a valid Nextflow/WDL/Airflow DAG schema where edges represent explicit file dependencies ($I/O$), not arbitrary UI ordering.
* **Filter Parameter Constants:** Strip out all generic environmental parameters (`threads`, `memory`, `scratch_dir`) from the parameter extraction gold; train the model solely on user-specified overrides and biological configuration variables.

---

### 5. Leakage: Prefix-Family Hash vs. Defensible Splitting

The current split strategy—**workflow-name-prefix family hash (~15% eval)**—is **insufficient** and guarantees severe train-eval contamination.

#### Why Prefix-Family Splitting Fails
1. **Tool Composition Duplication:** Bioinformatic pipelines are highly modular. Workflows `rnaseq_star_deseq2` and `transcriptomics_salmon_deseq2` might have different prefixes, but they share 80% of their DAG structure, identical downstream DE parameters, and identical autofix traces.
2. **Lexical Leakage via Boilerplate Queries:** A user prompt for pipeline A (`"Run variant calling with deepvariant on WGS"`) and pipeline B (`"Execute WGS deepvariant pipeline"`) will land on opposite sides of the split if their prefixes differ (e.g., `germline_` vs `wgs_`).

#### The Defensible Split Strategy
Implement a **Multi-Level Clustered Holdout**:

```
Catalog (4,200 Workflows)
  │
  ├── 1. Compute Pairwise Tool Jaccard Distance: J(W_i, W_j) = 1 - (|Tools_i ∩ Tools_j| / |Tools_i ∪ Tools_j|)
  ├── 2. Compute Structural Graph Edit Distance over Workflow DAGs
  └── 3. Louvain / Hierarchical Graph Clustering
        │
        ├── Cluster Alpha (All Variant Calling & Base Recalibration) ───> TRAIN
        ├── Cluster Beta  (All RNA-Seq / Transcript Quantification)  ───> TRAIN
        └── Cluster Gamma (Entirely Unseen Modality, e.g., Spatial)  ───> EVAL (OOD)
```

1. **Graph-Level Jaccard Clustered Split:** Cluster workflows based on tool-set overlap (Jaccard distance $\le 0.4$). Place entire clusters into either Train or Eval. Never allow a tool-combination variant to appear in Eval if an equivalent DAG exists in Train.
2. **Query Semantic Deduplication:** Embed all synthetic and natural queries using a biomedical dense embedder. Drop any eval query with cosine similarity $> 0.85$ to a training query.
3. **Target Evaluation Structure:**
   * **In-Distribution (ID) Eval (5%):** Random splits within training clusters (evaluates parameter extraction on known workflows).
   * **Out-of-Distribution (OOD) Eval (10%):** Entire workflow families and sub-domains held out (evaluates zero-shot decomposition and routing generalization).

---

### 6. Single Biggest Risk & Top 3 Fixes

#### The SINGLE Biggest Data-Quality Risk
**Label Space Schizophrenia across Training Tasks.**
The model is being trained to output three incompatible representations for the same underlying biological concepts: (1) free-form generic text from unguided teachers, (2) arbitrary non-standardized DB slugs, and (3) non-biological web-application plumbing from mined commits. The resulting model will experience catastrophic policy collapse, outputting unparseable JSON and hallucinated tool names at test time.

---

#### Top 3 Fixes BEFORE Training

| Priority | Action Item | Target Source | Concrete Execution Protocol |
| :--- | :--- | :--- | :--- |
| **FIX 1** | **Rerun Committee Distillation with Schema & Retrieval Constraints** | Committee Distillation (Routing, Param, WfGen) | Implement a strict candidate-selection harness. Provide the top-20 retrieved tool slugs and the workflow's formal JSON-Schema in the prompt. Constrain teacher generation to valid enum slugs and strict JSON parameter instances. Discard the free-form text. |
| **FIX 2** | **Purge Web-Dev / Maintenance Noise from Self-Mining** | Self-Mining (Commit Fixes, Docs QA) | Run an automated AST/extension audit over the 377 commit fixes and 1,996 QA pairs. Delete all instances touching non-pipeline code (frontend, REST APIs, CI/CD). Retain only execution errors and pipeline logic fixes (e.g., bash/Nextflow/R failures). |
| **FIX 3** | **Rebuild Splits via Tool-Graph Jaccard Clustering & Semantic De-duplication** | Entire Pool (`data_pool_v2`) | Deprecate the prefix-hash split. Cluster the 4,200 workflows via tool-set Jaccard distance and partition entire clusters. De-duplicate queries against a semantic embedding index ($\text{sim} < 0.85$) to establish a defensible benchmark. |