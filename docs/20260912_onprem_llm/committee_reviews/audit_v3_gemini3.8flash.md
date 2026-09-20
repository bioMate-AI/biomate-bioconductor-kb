[gemini] 6918 chars

Here is the adversarial audit of the BioMate post-training run.

---

### 1. DATA: Coverage, Quality, and Distribution Collapse

* **Severe Head-Bias & Domain Imbalance:** Transcriptomics accounts for ~55% of the evaluation (44/80) and saturates the SFT corpus. Rare biological modalities (epigenomics, metagenomics, specialized cancer genomics) are starving. 
* **18.6k Examples Is Mathematically Insufficient for 4,172 Workflows + 7,240 Tools:**
  * Average tool exposure across the entire SFT set is **<1.6 examples per tool** ($18,597 / 11,412$).
  * Accounting for Zipfian head-heavy distribution (DESeq2, Seurat, BWA-MEM, FastQC appearing hundreds of times), the bottom 60% of tools in your WKG have **zero** or **one** mention across the entire instruction tuning split.
* **Task Allocation Misalignment:**
  * Single-workflow routing (`rag_routing` 4,253 + `routing` 2,526 = 6,779; **36.5%**) dwarfs actual generative composition (`wfgen` 1,539 + `chaining` 605 = 2,144; **11.5%**).
  * You trained a **catalog lookup engine**, not a **workflow synthesizer**. When the catalog item is missing, the model has almost zero supervised density on synthesizing multi-tool fallback topologies from functional primitives.

---

### 2. DESIGN: The Cost of Skipping Mid-Training & Task Interference

* **Skipping Mid-Training Was a Critical Error:**
  * Base Qwen3 models do not have internal parametric knowledge of niche Bioconductor/BioPython tools (`rgsea`, `oncomix`, `methylGSA`, `magrene`). 
  * The 44.9M token corpus was specifically designed to inject token-level familiarity, function signatures, and ontology links. 
  * By going base $\to$ SFT directly, the models encountered niche tool tokens for the first time *under an instruction loss*, resulting in catastrophic hallucination or rejection when those tokens were queried.
* **Task Interference & Mode Collapse in the 27B:**
  * The 27B’s `composed_rate = 0.05` is direct evidence of **mode collapse driven by loss dominance**: `rag_routing` and `routing` reward short, high-confidence single-token / single-entity routing keys.
  * Because 27B has higher capacity, it over-optimized to the dominant task distribution (monolithic routing) and suppressed the complex multi-step JSON grammar expected by the compositional harness. The 4B underfit the routing shortcut, ironically preserving output format compliance (`composed_rate = 1.0`).

---

### 3. TASKS: Removal Eval Validity and Compositional Gaps

* **The Eval Tests Generalization That Was Never Supervised:**
  * The "out-of-catalog removal eval" forces the model to synthesize a sub-graph when the single target workflow node is deleted.
  * If the training set primarily teaches: *"When user asks X, emit single workflow Y"*, the removal eval creates an **out-of-distribution distribution shift**. The model either falls back to guessing a single alternative workflow (which misses the multi-step phase decomposition) or collapses to 0.
* **Retrieval Bottleneck Invalidates the Task:**
  * Retriever Recall@1 drops from **0.77** on random split to **0.40** on the honest FAMILY holdout (unseen workflows).
  * If the removal eval hides the workflow and its immediate family, the retriever fails to supply the right functional tool blocks in the context **60% of the time**. You are penalizing LLM generation for a catastrophic RAG recall failure.
* **Eval Metric Brittleness:**
  * Regex-based `composed_rate` counting `{step, workflow_or_action}` is fragile. The LLM Judge step-coverage eval is subject to semantic drift, position bias, and false negatives when alternative biological paths (e.g., edgeR instead of DESeq2, or custom R scripts instead of a packaged tool) achieve the same functional goal.

---

### 4. OUTPUT: Interpreting 0.30 (4B) and 0.40 (27B) vs. 0.54 (GPT-5-mini)

* **Not a Fair Generative Verdict:**
  * The 0.40 score for 27B is artificially depressed by formatting artifacts: answering with a single workflow or prose instead of the structured multi-step JSON penalizes the extraction parsing before the LLM-judge even evaluates step overlap.
* **The "Zero-Coverage" Divide:**
  * Removing the 20 zero-coverage cases from 27B reveals that its operational coverage on the remaining 60 cases is **~0.533** ($32.0 / 60$), matching `gpt-5-mini` (0.54).
  * **Conclusion:** The 27B model is **not uniformly mediocre**. It is **strictly bimodal**: frontier-grade when it knows the domain/format (22 cases $\ge 0.67$), completely dead when it hits un-retrieved niche tools or reverts to single-pick routing (20 cases $= 0$).

---

### 5. ERROR ANALYSIS: Root Causes & The Bimodality Phenotype

| Error Phenotype | Root Cause | Mechanism |
| :--- | :--- | :--- |
| **Niche Zero-Coverage** (`rgsea`, `methylgsa`, `icnv`) | **Dual Sparsity (Retriever + Parametric)** | The retriever hits 0 recall on unseen niche families; base model has never seen tool definitions because mid-training was skipped. Result: Complete hallucination or refusal. |
| **27B Bimodality** (22 high / 20 zero) | **Routing Shortcut vs. Format Rigidity** | High capacity allows 27B to cleanly bifurcate: when context permits, it resolves perfectly; when ambiguous, it defaults to the lowest-energy SFT attractor: single-workflow direct selection. |
| **4B Flat Smeared Distribution** | **Capacity Deficit** | 4B follows the JSON syntax template mechanically (composed 1.0), but lacks domain cross-attention to accurately match pipeline phase semantics (mean 0.30). |

* **Single Change with Highest Coverage Impact:**
  * **Context Injection of Upstream/Downstream WKG Subgraphs at Inference:** Do not rely on parametric weights or raw sparse retrieval for tool connectivity. Force the retriever to return the **1-hop precede/succeed tool graph** around the query concepts.

---

### 6. HIGHEST-PRIORITY FIX (Before v3 Compositional Training)

> **Execute the 44.9M Token Domain Mid-Training Run with Tool-Contract Pre-training, and Enforce Structured Output Grammar in the SFT Harness.**

Do **not** jump straight into another SFT iteration. 

1. **Burn the 44.9M tokens into the base models first (Continued Pre-Training / Domain Adaptation):**
   * Pack the WKG blocks, tool signatures, and bio-ontologies into document-level chunks with cross-entropy loss. This provides the weights with parametric density for long-tail tools (`rgsea`, `icnv`, etc.) before any task policy is learned.
2. **Re-balance the SFT Task Distribution:**
   * Cut `routing` down to $\le 15\%$.
   * Up-sample `decompose`, `wfgen`, and `interwf_decomp` to $\ge 40\%$ using **constrained JSON grammar decoding (e.g., XGrammar/Outlines)** so the 27B cannot emit single-pick shortcuts when a multi-step composition is required.
3. **Fix RAG Family Holdout:**
   * Augment retriever context with WKG graph transitions (explicit typed input/output edges) rather than relying on pure dense embedding similarity for niche tools.
