Here is an adversarial audit of the BioMate data pipeline across code, preprocessing, and data quality.

---

### 1. DATA QUALITY: Critical Defects in SFT & Corpus

#### A. Fatal Label Incoherence and Truncation in SFT Samples (Active in Provided Data)
Inspect the exact SFT samples provided:
1. **Sample 1 has NO user request whatsoever:** 
   Prompt ends right after candidates with `- Alphagenome Track Predic`. There is zero query text, yet the target is `nf-core/atacseq`. The model is being trained to guess `nf-core/atacseq` purely from an unconditioned candidate list.
2. **Sample 2 has egregious label mismatch (False Positive / Mislabel):**
   Request: `"I have label-free mass-spectromet[ry]..."`  
   Gold Target: `glmsparsenet` (a sparse network Cox/penalized regression R package).  
   Candidate #4 in that exact prompt: `nf-core/proteomicslfq` (the gold-standard nf-core workflow for **Label-Free Quantification mass-spec**). This directly teaches the model to hallucinate statistically obscure regression tools for high-throughput mass-spec proteomics.
3. **Sample 3 violates the routing contract (Target not in candidates):**
   Instruction: *"choose the single best-matching workflow and reply with ONLY its exact name from the candidates."*  
   Target: `spillr` (cytometry spillover compensation).  
   Candidate list: `demuxmix...`, `batchelor...`, `scthi...`, `censcyt...`, `flowbeads`, `statial...`, `-`.  
   `spillr` is **NOT IN THE CANDIDATE LIST**. Training the LLM on this forces it to ignore candidate boundaries and violate instructions.
4. **Hard truncation across all tasks:** Look at `Alphagenome Track Predic`, `mass-spectromet`, `3D geno`, `the default pseudomolecule fa`, and the trailing `-` in Sample 3. Your generation, parsing, or token-clipping script is blindly slicing characters or tokens at fixed boundaries without syntax validation, leaving truncated tokens and dangling hyphens.

#### B. The Parameter Schema-Validation Gap is Far Worse Than Integer Floats
Integer/count parameters (`nPerm=0.01`) are only the surface. Bioinformatics pipelines (Nextflow, Galaxy, Snakemake, CWL) have strict type enforcement that fails hard at runtime:
* **Log-scaled & percentage inverted domain bounds:** E.g., Q-value/FDR cutoffs (`qvalue=0.05` vs `-log10(qval)=1.3`), p-value thresholds mapped to percentages (`fdr=5` instead of `0.05`).
* **Mutually exclusive parameter co-occurrence:** Galaxy/nf-core schemas frequently specify conditional dependencies (e.g., if `protocol == "single-end"`, passing `--paired` or `--read2` crashes the workflow runner; if `--aligner star`, `--bwa` params must be omitted). Unchecked LLM generation injects invalid parameter unions.
* **String enum violations:** Genomic builds mapped to informal names (e.g., `genome="hg38"` vs `"GRCh38"`, or `"mm10"` vs `"GRCm38"`). If your schema requires valid enum strings, free-form SFT outputs will cause Nextflow schema validation errors (`nextflow_schema.json` exit code 1).
* **Missing required dependent paths:** Setting `--save_align_intermeds` without setting `--outdir` or specifying input channels.

---

### 2. PREPROCESSING: Verbalization & Deduplication Failures

#### A. Scraping Artifacts Leaking as "Domain Knowledge"
Look at the verbalized doc: 
`abslen_bed (version 1)... This tool is a temporary step to enable the Sanger TreeVal NF gap_finder workflow to be translated into Galaxy See https://github.com/fubar2/treeval_gal...`
* **Internal scaffolding & dead links:** You are mid-training on internal developer scratchpads, ephemeral porting shims, and orphaned repos.
* **Structural noise:** `## Examples\n[]` — empty JSON arrays rendered as literal markdown strings. 
* In `verbalize_sci`: `lines.append(f"{_humanize(k)}: {rv}.")` blindly concatenates arbitrary keys without type checking. If `rv` is a dict or nested list, `_render(v)` produces stringified Python reprs (`"{'min': 0, 'max': 1}"`).

#### B. Exact + MinHash Deduplication Blindspots
* **Version sprawl duplicates tools:** Galaxy and nf-core contain identical tools across revisions (e.g., `FastQC v0.11.7`, `v0.11.8`, `v0.11.9`, `v0.12.1`). Because the description prose is 95% identical but parameter flags shift slightly, standard MinHash often fails to cluster them if n-grams shift, or MinHash deduplicates them aggressively, dropping crucial parameter additions.
* **Ontology verbalization dilution:** Ontologies (GO, ChEBI, HPO) have thousands of circular parent-child definitions (e.g., "regulation of X", "positive regulation of X", "negative regulation of X"). Verbalizing them mechanically injects millions of near-identical tokens that artificially bias the attention prior toward boilerplate ontology syntax rather than scientific reasoning.

---

### 3. METHODOLOGY: Retriever Leakage & Train/Test Contamination

#### A. Severe Target Leakage (Random Holdout Fallacy)
The retriever evaluation is fundamentally invalid:
```python
src = [r for r in src if r.get("correct_workflow") in idx and r.get("query")]
random.shuffle(src)
ncut = int(len(src) * (1 - a.holdout_frac))
train_q, held_q = src[:ncut], src[ncut:]
```
* **Why this is broken:** If workflow $W_1$ (e.g., `nf-core/rnaseq`) has 20 labeled/synthetic queries in `src`, random shuffling puts 17 queries in `train_q` and 3 queries in `held_q`.
* The contrastive loss pulls the dense representation of the exact document $D_{W_1}$ directly toward the semantic cluster of those training queries. 
* When the model evaluates on `held_q`, it is **not testing retrieval generalization**; it is evaluating memorization of seen target workflow embeddings. The recall leap ($0.233 \to 0.767$) is a classic overfitting artifact.
* **The fix:** You MUST split by **Workflow / Target Class (GroupKFold)** or by **Temporal Release Date**. 
  * *Disjoint Workflow Holdout:* Workflows in `held_q` must NEVER appear as positive targets in `train_q`.
  * *Protocol Family Holdout:* Group all RNA-seq workflows together in test to verify that the retriever doesn't just memorize `rnaseq` keywords.

#### B. SFT Contamination
If the 15% retriever holdout queries (or the underlying real studies) share any overlap with the 17,265 SFT queries (specifically `routing` and `rag_routing`), your end-to-end BioMate evaluation is doubly contaminated: the retriever memorized the target doc, and the LLM memorized the candidate-to-answer mapping.

---

### 4. PARAPHRASE: Cheap Detection & Dropping of Degenerate Queries

The persona "bury in irrelevant lab context" causing cold-room/cage-rotation noise to out-weigh `nf-core/rnaseq` is a semantic drift problem. You need cheap, deterministic quality gates **without** calling another frontier LLM:

1. **Information-Need Inversion Filter (Directional Cross-Entropy / Mutual Information):**
   * Use your base bi-encoder or a lightweight cross-encoder (e.g., `bge-reranker-small`, 20ms per pair):
   $$\text{Score}(Q_{\text{paraphrase}}, \text{Doc}_{\text{gold}}) - \text{Score}(Q_{\text{original}}, \text{Doc}_{\text{gold}}) < -\tau$$
   * If the paraphrased query's retrieval similarity to the gold workflow drops by more than a calibrated threshold $\tau$ (e.g., $> 0.25$), the persona drowned the domain signal. Discard immediately.
2. **Domain Entity Retention Check (Fast NER / Token Set Intersection):**
   * Extract domain tokens (genes, assays, data types: BAM, FASTQ, mass-spec, single-cell, ATAC, ChIP) from the original request using a curated bioinformatics vocabulary or regex.
   * If $Q_{\text{original}}$ contained assay/data-modality tokens but $Q_{\text{paraphrased}}$ dropped them or diluted domain density below a minimal ratio:
     $$\frac{|Tokens(Q_{\text{paraphrase}}) \cap \text{DomainVocab}|}{|Tokens(Q_{\text{paraphrase}})|} < 0.05$$
     Drop it.
3. **Fix `split_request` Fragility:**
   * `split_request` uses `rfind(m)`. If the request contains another occurrence of `m` (or formatting variances like markdown `**Request:**` vs `Request:`), it fails or silently chops the request. 
   * Notice in SFT Sample 1, `Request:` was completely missing. If `split_request` returns `None`, what did your pipeline do? Did it fall back to taking the whole prompt or drop it? If it dropped into generation without guards, it produced corrupt data.

---

### 5. SINGLE HIGHEST-PRIORITY FIX

> **Purge and rebuild the SFT Candidate-Gold consistency filter, then kill the Random Retriever split.**

If forced to pick the **single most immediate technical blocker before allocating GPU hours**:

**Fix the SFT Ground Truth Corruption & Invalidation Gate.**

Mid-training on noisy text slightly degrades perplexity, and an overfitted retriever still retrieves plausible candidates. But **training an SFT model on prompts where the gold answer is missing from the candidate list (Sample 3) or where the label contradicts obvious candidate semantics (Sample 2: `glmsparsenet` instead of `proteomicslfq` on mass-spec) destroys model alignment instantly.** It conditions the model to hallucinate non-existent candidates and ignore prompt constraints.

**Actionable Execution:**
Run a strict validation script over all 17,265 SFT samples before training:
1. **Candidate Verification:** Assert `gold_answer in extract_candidates(prompt)`. If False, drop immediately.
2. **Non-Empty Request:** Assert `prompt` contains a well-formed, non-truncated request span ($>20$ chars, ending in valid punctuation, no truncated UTF-8/dangling hyphens).
3. **Purity Check:** Validate integer/float/enum parameters against Nextflow/Galaxy schemas using `jsonschema.validate()`. Drop/correct any record failing schema types.