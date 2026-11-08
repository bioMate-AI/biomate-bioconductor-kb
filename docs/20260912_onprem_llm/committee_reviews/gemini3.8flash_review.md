### Joint Committee Synthesis: BioMate Training Strategy Review

**Reviewers:**
*   **(A) Senior Bioinformatics Domain Expert:** Focus on workflow semantics, tool interfaces, biological validity, and pipeline execution reality.
*   **(B) Senior Deep Learning / LLM Post-Training Expert:** Focus on token economics, loss surfaces, distribution shifts, catastrophic forgetting, and agentic alignment.

---

### 1. Domain/General Mix Ratio & Token Budget

#### Critical Assessment
**The proposed 25% domain / 75% general mix for a 2-4B token run is an unjustified allocation of compute and data engineering.**
*   **DL Expert:** A 25/75 ratio with 75% general replay (FineWeb-Edu, The Stack) is typical when doing full-parameter continued pre-training on *under-trained base models* (e.g., Meditron-70B over Llama-2) to prevent representation collapse. However, Qwen-2.5/3.x is already pre-trained on >18T tokens, heavily saturated in scientific literature and code, and empirical results confirm your 27B is *already competitive with Max on RealBio*. Adding 1.5B–3B tokens of general replay via LoRA will largely burn compute without changing foundational reasoning.
*   **Bioinformatics Expert:** More critically, you only have **37M unique tokens** of proprietary internal data. Running a 2B–4B token budget means you are either:
    1. Re-cycling your 37M internal tokens 20–50+ epochs (leading to severe over-fitting on internal syntax, triple patterns, and hallucinations of static metadata), or
    2. Diluting your high-value tool/workflow operational tokens into a massive sea of generic PMC papers (~90%+ of your domain slice), turning an *agentic execution engine* into a generic *biomedical trivia model*.

#### Recommendation: 60% Specialized Code & Execution / 40% General Replay at 300M–500M Tokens Max
*   **Cap the token budget:** Drop the target from 2–4B to **300M–500M tokens**. Beyond 500M tokens, LoRA rank constraints ($r=64/128$) will saturate or experience orthogonal task interference.
*   **Invert the ratio on high-density domain data:**
    *   **50% Targeted Domain Code & Workflows:** Synthesize and unpack internal scripts, CLI help texts, Nextflow/WDL pipelines, and biological execution traces (target ~150M–250M tokens via augmentation).
    *   **10% Dense Bio-Literature / Protocols:** Bio-protocol, method sections of PMC papers (skip general abstracts).
    *   **40% Replay Anchor:** 20% high-quality Python/Bash from The Stack v2 + 20% FineWeb-Edu (to preserve formal reasoning and JSON/YAML adherence).
*   **Sweep Protocol:**
    Do not run a massive grid search. Run a **3-point perplexity + probe test** at 100M tokens:
    *   *Ratios to test:* 40/60, 60/40, 80/20 (Domain/General).
    *   *Decision Metric:* Held-out Nextflow/WDL syntax validation loss AND zero-shot pass rate on tool flag parsing, while monitoring GSM8K/HumanEval validation degradation (must remain $<2\%$ drop).

---

### 2. Corpus Composition Soundness

| Component | Current Status | Assessment | Concrete Action |
| :--- | :--- | :--- | :--- |
| **Hetionet KG (34.7k edges)** | Included | **DELETE.** Unrelated to agentic workflow execution. Hetionet contains compound-gene-disease edges; it does *not* teach an agent how to run `bwa-mem2` or wire an anndata object into Scanpy. | Remove entirely. Saves noise tokens and hallucinated biology during tool selection. |
| **Ontologies (EDAM, GO, SO, HPO, ChEBI)** | Included | **CONDITIONAL.** Raw OBO/OWL formats are toxic to LLMs (redundant IDs, syntax clutter). | Strip OBO stanzas. Convert EDAM into structured functional definitions: `[Operation: Cell Clustering] -> [Compatible Types: AnnData, SingleCellExperiment]`. Keep GO/SO only as synonym maps for retrieval, not continuous prose pre-training. |
| **Relational DB Triples (23k docs)** | Included | **HIGH RISK.** Naive verbalized triples (`subject - predicate - object`) produce degenerate, stilted text distributions that harm conversational coherence and code generation. | Convert triples into **synthetic technical documentation** (e.g., pseudo-man pages: "Tool X performs Operation Y on Input Z producing Output W under constraints C"). |
| **Workflow Code (17M tokens)** | Included | **UNDER-WEIGHTED.** 17M tokens is tiny for 4,200 workflows. Bioinformaticians write messy scripts, custom bash wrappers, and complex modular configs (subworkflows). | **3x this data.** Ingest nf-core repos, Galaxy IUC tool wrappers (XMLs), and Snakemake workflows. Parse and include standard Bash tool wrappers (`run_fastqc.sh`). |
| **Missing: CLI `--help` & Manpages** | **MISSING** | **CRITICAL GAP.** Parameter extraction fails because LLMs hallucinate CLI flags (e.g., `-t` vs `--threads` vs `-p`). | Scrape `--help` outputs, manual pages, and bioconda recipes for all 12,312 tools. This directly drives schema parameter adherence. |
| **Missing: Real Execution Traces / Logs** | **MISSING** | **CRITICAL GAP.** BioMate must diagnose errors, but pre-training corpus has zero execution logs (slurm logs, exit code 137 OOM, malformed FASTQ headers). | Ingest 50,000 Nextflow `.nextflow.log` files and STDERR/STDOUT dumps pairing failure traces with corrected scripts. |

---

### 3. Return on Investment (ROI) & Post-Training Staging

Your empirical findings already show:
1. Base 27B matches Max on RealBio.
2. Retrieval dominates routing (Recall@20 = 0.95).
3. Fine-tuning gains are brittle and prompt-format specific.

Given this, **a massive mid-training phase has the lowest ROI and highest risk of bricking your model's native zero-shot reasoning.**

```
ROI Hierarchy:
[Retriever & Schema Context Engine] >>>> [Format-Locked Joint SFT] >> [Grounded Execution RL] >>> [Domain Mid-Training (LoRA)]
```

#### Ranked Justification

1.  **Rank 1: Knowledge Retrieval & Dynamic Context Assembly (ROI: 9.5/10)**
    *   *Why:* 12,312 tools cannot fit reliably in weights without hallucinating flags across versions (e.g., Samtools 1.10 vs 1.19). A dynamic RAG engine feeding exact parameter schemas, verified type signatures, and relevant sub-DAGs into the prompt guarantees factual accuracy.
2.  **Rank 2: Format-Consistent Multi-Task SFT (ROI: 8.5/10)**
    *   *Why:* Directly drives your structured tasks (decomposition, parameter filling, auto-fix). Your empirical findings proved format-matched joint SFT yields real gains (+10.5pp routing, -32% param over-fill). This is where the model learns *agentic compliance*.
3.  **Rank 3: Grounded Execution RL / DPO (ROI: 7.0/10)**
    *   *Why:* BioMate tasks feature verifiable terminal states: Does the generated Nextflow script pass `nextflow run -preview`? Does the JSON parameter block validate against the JSONSchema? Direct alignment via DPO or PPO using a synthetic sandbox validator enforces strict adherence better than SFT alone.
4.  **Rank 4: Domain Adaptive Mid-Training (ROI: 3.5/10)**
    *   *Why:* Base Qwen-27B already possesses general biological comprehension. Mid-training is only justifiable to bridge the syntax gap for specialized DSLs (Nextflow DSL2, CWL, tool JSON schemas). If done carelessly, it creates catastrophic forgetting and format divergence.

*Strategic Verdict:* **Demote Mid-Training.** Cut it to a lightweight ~200M token "Warmup Adapter" targeting strictly Nextflow/WDL DSL2 code, CLI manuals, and execution logs, or skip it directly to SFT if timelines are constrained.

---

### 4. SFT Data Quality, Yield, and Generalizability

Your SFT dataset has **1,834 examples across 6 tasks**. This is critically under-dimensioned and structurally imbalanced for enterprise-grade deployment.

#### Critical Flaws & Remediation

```
Current Distribution vs. Recommended Distribution:
Current: [ Routing: 529 | Param: 384 | Decomp: 341 | WfGen: 320 | AutoFix: 211 | Protocol: 49 ] Total = 1,834
Target:  [ Routing: 1,500 | Param: 2,500 | Decomp: 1,500 | WfGen: 1,000 | AutoFix: 1,500 | Interp: 1,000 ] Total = ~9,000
```

1.  **The Parameter Extraction Bottleneck (Yield ~16%):**
    *   *Diagnosis:* A 16% generation yield indicates your schema verification gate rejects 84% of synthetic samples due to hallucinated parameter names, wrong types, or missing required values.
    *   *Fix:* Stop using unstructured synthetic generation. Use **Inverse Execution Mining**:
        *   Parse the 4,200 verified workflows.
        *   Extract the real parameter maps actually used in production.
        *   Use an LLM to generate the *natural language instructions* that would prompt those exact configurations (back-translation). This yields 100% schema-valid ground-truth pairs without rejection waste.
2.  **Protocol Task Under-Representation ($N = 49$):**
    *   *Diagnosis:* 49 examples is statistically negligible; the weights will treat this as noise or over-fit to the specific 49 biological assays represented.
    *   *Fix:* Either **drop the protocol task entirely** from this SFT phase (handle it via pure RAG over Bio-protocol) or synthetically bootstrap it to at least 500 examples using wet-lab protocol decompositions (e.g., protocol to execution DAG).
3.  **Decomposition Intra-Workflow Limitation:**
    *   *Diagnosis:* Limiting decomposition to intra-workflow operations creates an agent that cannot handle realistic multi-omic user queries (e.g., "Run RNA-seq QC, call variants with GATK, and correlate with this ATAC-seq peak file").
    *   *Fix:* Generate cross-workflow DAGs. Synthesize queries that require chaining independent modules (e.g., [Upstream Workflow: CellRanger] $\rightarrow$ [Intermediary: Data Converter/Filter] $\rightarrow$ [Downstream Workflow: Seurat Integration]).
4.  **Format-Overfitting Defense:**
    *   *Diagnosis:* You observed that gains on one prompt format failed to transfer to production formats.
    *   *Fix:* Implement **Format Jittering** during SFT:
        *   Vary whitespace, delimiter keys (`### Response` vs `Assistant:` vs `<|im_start|>assistant`), system prompt verbosity, and tool schema ordering across a fixed set of 3 equivalent production templates.
        *   Explicitly train on partial context (e.g., missing metadata fields) so the model learns robust fallback handling rather than memorizing exact key sequences.

---

### 5. Single Biggest Risk & Top 3 Actionable Changes

#### The Single Biggest Risk
**Format Collapse and Operational Drift induced by Uncontrolled Mid-Training.**
Pouring ungrounded academic text (PMC/Hetionet/triples) into Qwen-27B via continuous pre-training will destabilize its carefully tuned instruct-following capabilities and degrade its JSON/schema adherence. This creates an unrecoverable gap between the model's weight representations and the strict syntactic formatting required by your downstream agentic execution engine.

---

#### Top 3 Actionable Changes

1.  **Re-Engineer Corpus: Purge Trivia, Inject Execution Reality (CLI + Logs).**
    *   *Action:* Immediately drop Hetionet and raw OBO ontologies. Convert the DB triples into synthetic manpages. Scrape CLI `--help` specs for all 12,312 tools and ingest Nextflow/Bash execution error logs. Downscale the Mid-Training token target from 2–4B to **300M tokens max**, composed of 60% bio-code/CLI/logs and 40% code/instruction replay.

2.  **Bootstrap SFT Set via Reverse Mining (Target: 8k–10k examples).**
    *   *Action:* Solve the 16% parameter yield and small dataset size by parsing the internal 4,200 verified workflows backwards. Extract real parameter configurations, execution DAGs, and tool invocations, and prompt a model to generate the corresponding user requests. Ensure decomposition spans cross-workflow scenarios, and eliminate or expand the $N=49$ protocol task.

3.  **Implement Schema-Constrained Reinforcement Learning / DPO instead of Heavy CPT.**
    *   *Action:* Shift compute budget from pre-training to post-training alignment. Set up an automated evaluation harness:
        $$\mathcal{R}_{\text{task}} = \alpha \cdot \mathbb{I}(\text{Valid JSON/Schema}) + \beta \cdot \text{Tool Selection F1} + \gamma \cdot \mathbb{I}(\text{Nextflow Lint Pass})$$
        Use this deterministic verification harness to generate preference pairs (DPO) on edge cases where parameter filling or auto-fix fails. This directly targets your production tasks with zero risk of catastrophic forgetting.
