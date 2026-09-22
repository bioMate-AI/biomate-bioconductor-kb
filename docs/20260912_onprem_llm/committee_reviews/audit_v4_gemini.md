# AUDIT REPORT: TASK DEFINITION & DATA SETTING (BIOMATE v4)

**Reviewers:** 
- **[BIO]** Senior Bioinformatics Domain Expert  
- **[MLE]** Senior ML Evaluation & LLM-Training Expert  

---

## 1. Task Definition Audit: Is "Removal Reconstruction" a Valid Proxy?

### The Consensus
**No.** While removing a known workflow from the candidate list simulates *catalog absence*, forcing the model to reconstruct an equivalent multi-step plan evaluated against static textual steps measures **semantic paraphrasing of standard pipeline phases**, not executable composition or bioinformatic validity.

### Remaining Validity Threats Post-"Tool-Agnostic" Fix

1. **The "Hallucinated Substitutability" Fallacy [BIO]:**
   In bioinformatics, equivalence is rarely 1:1. If you remove `Salmon` from candidate tools, replacing it with `STAR` + `featureCounts` requires downstream steps to handle BAM files, coordinate sorting, multi-mapping reads, and strand specificity differently. Scoring equivalence at the conceptual level (*"quantify gene expression"*) ignores whether the substitute tools are mathematically or computationally compatible with the inputs and downstream steps (e.g., passing TPM vs. raw counts into `DESeq2`).

2. **The "Cheating via `RUN_CODE`" Loophole [MLE]:**
   The prompt permits `GENERATE/RUN_CODE`. A 4B or 27B model can bypass the hard retrieval/composition constraint by generating a generic Python/R snippet (e.g., `system("run_pipeline.sh")` or a generic pseudo-function). If the LLM judge checks conceptual coverage, writing `"I will run custom script to normalize and estimate dispersion"` gets full credit without proving the model knows *how* to substitute the tooling or respect catalog constraints.

3. **Retriever Coupling & Out-of-Distribution Input [MLE]:**
   The candidates supplied are the retriever’s top-10 *after* dropping the gold workflow. If retriever recall on unseen families is 0.40, the model is fed 6–10 irrelevant or weakly relevant distractor tools. The task conflates **distractor rejection under poor retrieval** with **creative workflow synthesis**.

### Proposed Task Reformulation
Transform the task from **Unconstrained Plan Generation** to **Executable Directed Acyclic Graph (DAG) Constraint Satisfaction**:
* **Inputs:** Detailed Query + Strict Catalog Context (Available Tools + Schema: Input/Output MIME/data types).
* **Action Space:** Explicitly typed nodes: either `TOOL_INVOCATION(tool_id, mapped_args)` or `RUN_CODE(runtime, validated_script)`.
* **Output Validity:** Strict type-check: Node $N+1$ must ingest the exact artifact schema produced by Node $N$ (e.g., output of tool $A$ must be `format: AnnData[raw]`, matching tool $B$'s requirement).

---

## 2. Metric Audit: LLM-Judged Step Coverage

### Primary Confounds

1. **Information Leakage via the Query (The "Reading Comprehension" Trap) [MLE]:**
   Because gold steps were rewritten from the query (e.g., query mentions *"batch and sex covariates"* $\rightarrow$ gold step: *"fit count model with batch+sex covariates"*), the eval is largely testing query extraction. A model that simply echoes back the query prompt in imperative bullet points scores $\ge 0.70$ on step coverage without selecting a single viable tool.

2. **Judge Granularity & Verbosity Bias [MLE]:**
   `gpt-5-mini` exhibits typical LLM-judge pathologies:
   * **Boilerplate leniency:** A generic 7-phase bioinformatics template (*QC $\rightarrow$ Filter $\rightarrow$ Norm $\rightarrow$ DimRed/Model $\rightarrow$ Test $\rightarrow$ Annotate $\rightarrow$ Export*) automatically hits 4–5 of any 6 gold steps.
   * **Inconsistent alignment:** A step like *"normalize + estimate dispersion"* is counted by the judge as covered if the model says *"preprocess data and scale"*, obscuring critical domain omissions (e.g., size-factor vs. library-size vs. FPKM).

3. **Ignoring False Positives (Precision = 0) [BIO]:**
   The metric evaluates **Recall** (fraction of gold steps covered). It completely fails to penalize **Bioinformatic Nonsense** (e.g., running `log2(x + 1)` transform *before* feeding data into `DESeq2` or `edgeR`, which requires discrete counts; or running batch correction with `Combat-seq` on normalized CPM). A plan with 5 correct steps and 2 workflow-breaking errors receives 100% step coverage.

### Recommended Metric: Dual-Faceted Executable Score ($F_\beta$ + Constraint Penalty)

$$\text{Plan Score} = \text{Recall}_{\text{goals}} \times (1 - \text{Penalty}_{\text{invalid\_transitions}}) \times \mathbb{I}(\text{Synthesizable})$$

1. **Structural Tool-Type Alignment:** Graph parser validates that outputs of substitute steps match input prerequisites of subsequent steps.
2. **Negative Constraint Check (Adversarial Judge):** Specifically prompt the judge to search for *Disqualifying Bioinformatic Errors* (data leakage between train/test, invalid normalization prior to count-modeling, format incompatibility). Deduct 0.25 per fatal violation.
3. **Metric Validation Protocol:**
   * **Human Agreement Calibration:** Take 30 cases; 2 bioinformaticians blindly score them. Compute Cohen’s $\kappa$ with `gpt-5-mini`. Target: $\kappa \ge 0.75$.
   * **Degenerate Baseline Ablations:** Run two control models through the eval:
     * *Null-Model:* Echoes query sentences as numbered steps.
     * *Generic-Template:* Injects a static 5-step standard pipeline for every query.
     * *Pass Condition:* Both degenerate baselines must score $< 0.15$. If they score $> 0.35$, the metric is uncalibrated.

---

## 3. Data Setting Audit (Eval Set)

### Threats & Vulnerabilities

| Threat | Impact | Severity |
| :--- | :--- | :--- |
| **Deriving Gold from Query** | Introduces structural circularity. Tests reading comprehension, not tool-grounded synthesis. | **CRITICAL** |
| **Transcriptomics Skew** | 44/80 (55%) transcriptomics cases overweights counts/differential expression at the expense of structural biology, phylogenetics, metagenomics, and variant calling. | **HIGH** |
| **Sample Size ($n=80$)** | Underpowered. For micro $\Delta \approx 0.01$ (0.483 vs 0.493), the 95% CI with $n=80$ and $\sigma \approx 0.25$ is $\pm 0.055$. The mid-train comparison was completely unpowered. | **HIGH** |
| **Lack of Difficulty Strata** | Cases where drop-in 1:1 substitutes exist (`DESeq2` $\leftrightarrow$ `edgeR`) are mixed with cases requiring multi-tool decomposition (`cellranger` $\leftrightarrow$ `STARsolo` + `custom_qc`). | **MEDIUM** |

### How to Construct a Defensible Held-Out Eval

1. **Gold Source Decoupling:**
   * Gold steps must be derived from an **independent expert design** specifying minimal analytical milestones required to answer the biological intent, **completely isolated from both the original workflow text and the user query wording**.
2. **Stratification across 5 Core Super-Domains:**
   * Bulk/Single-Cell Transcriptomics (max 25%)
   * Genomics & Variant Calling (WGS/WES/Structural Variants) (25%)
   * Proteomics / Metabolomics / Mass Spec (20%)
   * Structural Biology & Epigenomics (ChIP/ATAC/Hi-C/AlphaFold) (15%)
   * Metagenomics & Microbial Phylogenetics (15%)
3. **Power Analysis for Eval Sizing:**
   * To reliably detect a meaningful shift ($\Delta \ge 0.05$ at $\alpha = 0.05, 1 - \beta = 0.80$), the evaluation set must be **$N \ge 220$ stratified, non-overlapping cases**.
4. **Three Difficulty Tiers:**
   * **Tier 1 (Direct Tool Replacement):** Identical input/output format; 1 substitute tool available.
   * **Tier 2 (Composite Expansion):** 1 monolithic removed tool must be replaced by a chain of $\ge 2$ finer-grained tools.
   * **Tier 3 (Zero-Retrieved Tool / Pure Synthesis):** Model must generate an executable R/Python script because no catalog candidate matches.

---

## 4. Data Setting Audit (Mid-Training: Why Was It a Wash?)

### Diagnosis: Corpus, Dose, Lever, or Evaluation?

| Hypothesis | Assessment | Evidence |
| :--- | :--- | :--- |
| **1. Under-Dosing (Definite Contributor)** | **CONFIRMED** | 800 steps $\times$ seq 1024 $\times$ batch 16 = **13.1M tokens trained**. On a 46.4M corpus with 50–75% FineWeb replay, the model saw at most **3.2M to 6.5M domain tokens**. This is $< 0.15$ epochs. A 4B model will not shift parametric weights on 5M novel domain tokens. |
| **2. Sequence Length Truncation** | **CONFIRMED** | `seq-1024` truncates workflow definitions, tool manuals, and biological scripts mid-stream. It destroys long-range dependency representations of multi-step pipelines. |
| **3. Evaluation Insensitivity** | **CONFIRMED** | If the eval primarily measures query reading comprehension (see Sections 1 & 2), domain-specific pretraining provides zero marginal advantage over base instruction following. |
| **4. Structural Lever Mismatch** | **HIGH LIKELIHOOD** | Unstructured CPT (next-token prediction on text/code) does not teach the model how to reason over *catalog schemas* or graph substitutions under hard constraints. |

### Diagnostic Experiment Protocol to Determine Future Viability

Do not run another full mid-training run without verifying domain absorption via the following ladder:

```
[Phase 1: Domain-Knowledge Probing]
  ├── Multi-choice Bio-API & Tool I/O Probe (1,000 facts never in base model)
  │     ├── Base Model Score vs.
  │     └── Mid-Trained Model Score
  │           └── If Delta ~ 0 -> Model did not absorb corpus (Fix dose/architecture)
  │
[Phase 2: Dose & Context Sweep] (Only if Phase 1 passes)
  ├── Context window: 1024 -> 4096 (Preserve entire pipelines)
  ├── Dose: Sweep 1 epoch (46M tokens) vs. 3 epochs (138M tokens)
  └── Target: Mid-train loss convergence on domain validation set (perplexity drop > 15%)
```

---

## 5. The Correct Setup: Moving Out-of-Catalog Composition

To genuinely improve and measure out-of-catalog composition, shift from passive text generation to **constrained programmatic planning**:

### Data Setting (SFT & Training)
1. **Tool Schema Conditioning:** Structure tool documentation into strict, uniform JSON/YAML declarations (`inputs`, `outputs`, `prerequisites`, `assumptions`).
2. **Synthetic Counterfactual Perturbation (Data Augmentation):**
   * Take the 18,597 SFT dataset.
   * Systematically run a "Tool Drop" transform: For 30% of multi-step SFT examples, drop the primary tool from the prompt context, forcing the target completion to synthesize the alternative path (either via secondary tools or a robust `RUN_CODE` block).
   * This directly aligns SFT optimization with the out-of-catalog test distribution.

### Task Definition (Inference & Evaluation)
1. **Contract-Driven Plan Synthesis:**
   The output must be a structured execution plan (JSON/YAML DAG):
   ```yaml
   steps:
     - step_id: 1
       action: TOOL_INVOCATION
       tool: "fastp"
       inputs: [raw_reads]
       outputs: [clean_reads, qc_report]
     - step_id: 2
       action: GENERATE_CODE
       runtime: "python:3.11-biopython"
       replaces_missing_tool: "custom_adapter_filter"
       code_signature: "def clean(input_path: Path) -> Path:"
   ```
2. **Static Validation Engine:**
   Run the generated DAG through an automated static checker:
   * Graph integrity (is it a valid DAG? Any cycles?).
   * Type compatibility (does Step 2 accept the data format output by Step 1?).
   * Catalog adherence (did it hallucinate a tool not in the top-10, or did it properly route to `GENERATE_CODE`?).

---

## 6. The Verdict

### The SINGLE Biggest Threat to Validity
> **The current evaluation framework tests *Query Paraphrasing into Standard Biological Headers*, not out-of-catalog composition.** Because the ground-truth steps are derived directly from the user query, and the LLM judge only computes conceptual coverage without checking input/output data compatibility or penalizing bioinformatic anti-patterns, any small model capable of echoing the query prompt achieves an inflated score (~0.50), rendering both the SFT comparisons and the mid-training wash completely uninterpretable.

---

### Top 3 Actionable Priorities

1. **Decouple and Stratify the Eval Set (Stop Query Leakage):**
   * Freeze the query. Have independent domain experts write the analytical ground truth **without seeing the query text**.
   * Rebalance the 150/220-case eval set to cap transcriptomics at 25% and represent the other 4 core biological domains.
   * Run the *Null-Model Echo Baseline*; if it scores $> 0.15$, throw out the metric prompts.

2. **Upgrade the Evaluator to Include Negative Bioinformatic Constraints:**
   * Incorporate a strict bioinformatic error checklist into the LLM judge (e.g., library-size normalization applied before raw-count models, unstranded tools on stranded protocols, invalid BAM/VCF tooling).
   * Penalize the score multiplicatively for every fatal bioinformatic incompatibility.

3. **Re-Architect Out-of-Catalog Training via SFT Counterfactuals, Not Unstructured CPT:**
   * Shelve further mid-training runs until an SFT-level intervention is tested.
   * Introduce "tool dropout" directly into the 18.5k SFT dataset (masking gold tools and teaching the model to branch to alternatives or explicitly write code wrappers).
   * This attacks compositionality directly through supervised alignment rather than hoping the model infers complex substitution logic from 13M tokens of next-token pretraining.