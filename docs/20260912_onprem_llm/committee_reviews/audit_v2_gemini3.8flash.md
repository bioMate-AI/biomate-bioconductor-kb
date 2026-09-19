[gemini] 6527 chars

Here is the adversarial audit of your BioMate SFT dataset based on the complete records. While v1 suffered from truncation artifacts, **v2 reveals severe semantic data corruption, broken DAG logic, and broken parameter-validation training targets.**

---

### 1. Fatal Grounding & Label Defects (Smoking Guns in Provided Samples)

*   **Hallucinated Domain in `interwf_decomp` (Critical Data Contamination):**
    *   **Input:** Multi-part request clearly asks for (1) bulk RNA-seq batch correction (`SummarizedExperiment`) and (2) **raw single-cell RNA-seq processing** (UMI counts, cell QC, doublets, normalization, DE).
    *   **Gold Label:** 
        ```json
        [
          {"sub_task": "transcriptomics analysis", "workflow": "buscorrect_bus_correct_summarized_experiment", "order": 1, "depends_on": []},
          {"sub_task": "metabolomics analysis", "workflow": "phenomis", "order": 2, "depends_on": []}
        ]
        ```
    *   **Defect:** `phenomis` is a Galaxy/W4M **metabolomics** suite. The gold label assigned metabolomics to a single-cell transcriptomics request. This is a severe synthetic-generation artifact (likely prompt leakage or misalignment in the multi-part generation script). If trained on this, the model will hallucinate unrelated omics workflows.
*   **Candidate Collision in `rag_routing` (CUT&Tag vs. CUT&RUN):**
    *   **Input:** Explicitly specifies `[CUT&Tag]`.
    *   **Candidates include:** Both `Cutandtag Alignment Spikein` and `nf-core/cutandrun`.
    *   **Gold Label:** `nf-core/cutandrun`.
    *   **Defect:** While `nf-core/cutandrun` can process CUT&Tag data, having a dedicated CUT&Tag workflow in the candidate set without explicit disambiguation logic makes this label arbitrary. The retriever provided an exact modality match (`Cutandtag Alignment Spikein`), but the gold target penalized it.
*   **Open-Vocabulary Routing without Candidates (`routing` Ex 2):**
    *   Example 2 gives no candidate list and demands the model emit `lea_gea_least_squares_lfmm2` from memory across 4,200 workflows. This causes high hallucination rates on rare Bioconductor scripts. Open routing across 4,200 classes should be dropped in favor of `rag_routing`.

---

### 2. Decomposition & DAG Integrity

*   **Broken Dependency Pointers (`decompose` Ex 1):**
    *   **Gold Output:**
        *   Step 1: `Prepare binary effect matrix` (`order: 1, depends_on: []`)
        *   Step 2: `Run epiNEM network inference` (`order: 2, depends_on: []`)  <-- **Bug**
        *   Step 3: `Plot the inferred network structure...` (`order: 3, depends_on: [1]`) <-- **Bug**
    *   **Defect:** 
        1. Step 2 (inference) runs with `depends_on: []`, meaning it executes in parallel with or prior to input preparation.
        2. Step 3 (plotting inferred network) depends on `[1]` (input prep) instead of `[2]` (inference).
    *   Training on this will teach the LLM to emit topologically invalid execution graphs that fail in pipeline orchestrators (Nextflow/Airflow/Snakemake).

---

### 3. Parameter Extraction & Schema Restraint

*   **Severe Under-Reporting Bug in `cond_param` & `clarify`:**
    *   In both examples, the schema lists 7 to 16 **`required`** parameters (`gem`, `seed.size`, `iterations`, `cuts`, `splits`, `bam_files`, `regions`, etc.).
    *   The user requests contain **none** of these low-level technical parameters.
    *   **Gold Labels:**
        *   `cond_param`: `{"clarify_needed": ["splits"]}` (Only 1 of 7 required missing parameters flagged).
        *   `clarify`: `{"clarify_needed": ["extend_reads"]}` (Only 1 of 13 required missing parameters flagged).
    *   **Impact:** The synthetic pipeline that generated these targets evidently picked a single random missing parameter rather than identifying the full set of missing required inputs. Training on this will teach BioMate to fixate on one arbitrary missing flag while silently ignoring other missing required parameters.
*   **Dirty Extraction in `param` Ex 1:**
    *   Input: `Candidate parameter: exclude=sgc.`
    *   Gold: `{"exclude": "X", "sgc": "X"}`.
    *   Prompt artifact: `sgc` was an internal abbreviation or prompt artifact that leaked into both key and value.

---

### 4. Task Design: What BioMate is Missing

Your current 11 tasks stop at decomposition and parameter extraction. In real-world workflow operations, BioMate will fail unless you include:

1.  **Input/Output Modality & Type Verification (Pre-flight):** Checking if Tool A's output format (e.g., `BAM`, `narrowPeak`, `AnnData h5ad`) matches Workflow B's input format (e.g., `SingleCellExperiment`, `counts.tsv`).
2.  **Infrastructure & Resource Profiling:** Bioinformaticians routinely need resource sizing (e.g., nf-core `--max_memory`, `--max_cpus`, Nextflow profile selection for SLURM/AWS Batch based on sample size and genome size).
3.  **Run Failure / Log Triage:** When a Nextflow/Galaxy job fails with OOM, exit code 137, missing index, or uncompressed fastq errors, BioMate must be trained to parse standard error logs and suggest parameter remediation.

---

### 5. Coverage & Distribution Risks

*   **15,254 examples across 4,200 workflows = ~3.6 examples/workflow average.**
    *   `interwf_decomp` has only **354 examples** for 4,200 workflows across 36 domains. This is critically starved. With complex cross-domain workflows (e.g., Proteomics + RNA-seq, Spatial + scRNA), 354 examples guarantees combinatorial collapse.
    *   `rag_routing` (4,244) and `routing` (2,538) consume **44% of the entire dataset**. The model is over-trained on naming workflows and under-trained on correctly executing and configuring them.

---

### 6. Single Highest-Priority Action Before GPU Training

> **Purge and Regenerate the `cond_param`, `clarify`, and `decompose` Datasets Using Deterministic Schema Validation.**

Do not train on the current synthetic labels. 
1. **Fix `clarify_needed`:** Run an automated validator over all parameter schemas. If a parameter is marked `required` and does not appear in the extracted parameter dict, it **must** appear in `clarify_needed`. A gold target with 6 missing required parameters that only asks for `["splits"]` will ruin conversational validation.
2. **Fix DAG Dependencies:** Run a networkx/DAG topological sorter over all `decompose` and `interwf_decomp` examples. Reject or correct any example where downstream steps depend on data-prep steps instead of the analytical producer steps, and remove all cross-omics hallucinations (like `phenomis` for single-cell).
