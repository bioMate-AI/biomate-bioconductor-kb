As a dual-expert committee representing both **Senior Bioinformatics Domain Expertise** and **Senior Deep Learning/LLM-Training Expertise**, we have rigorously reviewed your training-data preparation plan. 

Your empirical findings—specifically that your base 27B is already competitive, gains are prompt-format-specific, and routing relies heavily on retrieval—are excellent anchors. However, your current data plan contradicts some of your own established design principles.

Here is our concrete, actionable review of your pipeline.

---

### 1. The 25/75 Mix Ratio & Token Budget: Justification & Recommendations
**Verdict: UNJUSTIFIED and mathematically risky.** 
Your internal domain corpus is ~37M tokens. If domain data is 25% of a 2B–4B token run, you need 500M–1B domain tokens. This means you are either padding massively with external peS2o/PMC (diluting your specific tool-focus) or repeating your 37M internal tokens 14 to 27 times. Repeating CPT data >4 epochs on a 27B model guarantees catastrophic overfitting and loss of general reasoning. Furthermore, doing CPT via LoRA inherently protects against forgetting, making a 75% general replay buffer excessive and computationally wasteful.

*   **Recommended Ratio:** **80% Domain / 20% General** (FineWeb-Edu/Code only). Since you are adapting to a highly specific schema/graph, density of signal matters more than broad regularization.
*   **Token Budget:** Shrink the run to **~150M - 300M tokens total** (max 3-5 epochs over your internal data + high-quality external bio-code). 
*   **Sweeping & Optimum Definition:** Sweep ratio (e.g., 50/50, 80/20, 100/0) and learning rate on a sub-scale proxy model (e.g., Qwen-1.5B or 7B). The optimum is defined by the crossover point where **validation perplexity on held-out internal Nextflow/JSON schemas minimizes** while **MMLU/HumanEval zero-shot scores do not degrade by more than 2-3%**.

### 2. Corpus Composition Soundness
**Verdict: Misaligned with the "Workflow Assistant" objective.**
*   **Over-weighted / Off-topic:** *Hetionet, HPO, and PMC oa_comm.* Hetionet/HPO are disease, drug, and phenotype graphs. BioMate is a *tool and workflow* agent. General PMC papers contain massive amounts of biological background noise that will not help a model write Nextflow or route to `fastqc`.
*   **Missing / Under-weighted:** **Execution Logs and Traces.** You have workflow code (17M) and tutorials, but zero mention of stdout/stderr, compilation errors, or runtime traces. If you want a model to do "error DIAGNOSIS", it *must* see the stack traces paired with the code.
*   **Verbalized KGs & Ontologies:** Raw EDAM/GO/SO are useful, but flat triple verbalization (e.g., "Tool A operates_on Data B") is weak. You must synthesize *graph-walks* (e.g., "To go from raw reads to variant calls, we use Tool A which takes Data B, outputting Data C, which is then fed into Tool D"). 

### 3. ROI of Mid-Training vs. SFT + RAG + RL
**Verdict: Mid-training has the LOWEST ROI and contradicts your own design principles.**
You established: (a) base is competitive, (b) gains are prompt-format-specific, and (c) knowledge belongs in retrieval (RAG). Mid-training is for injecting *parametric knowledge* and *broad domain vernacular*. If knowledge is handled by RAG and skills/formats by SFT, mid-training is essentially dead weight and risks negative transfer.

**Ranked ROI for your specific use-case:**
1.  **Retriever / RAG Pipeline (Highest):** This is your engine. If recall@20 = 0.95, focus on precision@3 and dynamic schema injection.
2.  **SFT (High):** This is where the model learns your exact JSON/DAG outputs and prompt formats. Essential for your agentic behavior.
3.  **RL (Medium-High):** Grounded reward (verifiable execution/schema checks) will directly fix your identified "-32% over-fills" in parameter extraction by penalizing hallucinations. 
4.  **Mid-Training (Lowest):** Only useful for teaching the model the syntax of Nextflow/Bioconductor if the base Qwen lacks it, which Qwen 27B likely doesn't. 

### 4. SFT Data: Generalizability, Accuracy, and Gaps
**Verdict: Dangerously small, heavily gapped, and lacking RAG-alignment.**
1,834 examples across 6 tasks is too small for a 27B model to learn robust, multi-step agentic skills, especially given the exact-format constraint.
*   **Gaps in Data:**
    *   *Autofix (211) & Protocol (49):* Negligible. A model cannot learn error diagnosis across 12,312 tools from 211 examples. Drop Protocol entirely or synthesize 1,000+ examples using an upstream frontier model.
    *   *Decomposition (341):* Intra-workflow only is a critical flaw. Real bioinformatics queries are often vague, cross-domain intents (e.g., "process these scRNA-seq cells and do a trajectory analysis"). You must include *inter-workflow* DAGs.
    *   *Negative/Null examples missing:* Parameter extraction (384) needs examples where the user query *lacks* the required parameters, teaching the model to ask for clarification rather than hallucinating defaults.
*   **Format-Overfit vs. Generalizability:** Because your SFT is highly formatted, it *will* overfit. To ensure it generalizes across all 12,312 tools, you must implement **RAG-SFT**. The SFT prompts must include the retrieved Tool AI DB context exactly as they will in production, teaching the model to *read the prompt context* rather than relying on parametric memory.

### 5. The Single Biggest Risk & Top 3 Changes
**The Single Biggest Risk:** 
**Training Data / Inference Mismatch (The RAG Gap).** You are preparing to do Mid-Training and SFT on static, inherent knowledge, but in production, you plan to use RAG for volatile cataloging. If the SFT data does not explicitly train the model to attend to, extract from, and strictly obey injected RAG context, the model will suffer severe hallucination and ignore the retriever entirely.

**Top 3 Changes We Strongly Recommend:**
1.  **Skip Mid-Training; Reallocate Compute to Synthetic SFT Data:** Cancel the 2B-token mid-training. Use that compute/budget to have a frontier model (or Qwen-Max) synthesize 15,000–30,000 highly diverse, verified SFT examples from your 37M token corpus. 
2.  **Implement RAG-SFT (Context-Grounded SFT):** Every routing, decomposition, and parameter-extraction example in your SFT set must be formatted *exactly* like a production RAG prompt. Include 2-3 relevant retrieved tools and 2-3 distractor tools in the prompt. Train the model to select and ground its output *only* from the provided context.
3.  **Inject Execution Logs into SFT/RL:** Scrap Hetionet and general PMC papers. Harvest actual Nextflow/Bioconductor execution logs (successes and tracebacks). Feed these into your Autofix SFT and use execution-success as the definitive reward signal for your RL phase.
