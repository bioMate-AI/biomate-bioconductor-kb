[gemini] 9610 chars -> /Users/kky/biomate-review/docs/20260912_onprem_llm/committee_reviews/audit_gemini.md

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
* **Missing 
