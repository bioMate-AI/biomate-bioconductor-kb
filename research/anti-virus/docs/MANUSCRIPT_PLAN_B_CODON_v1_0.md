# Codon-optimized mRNA construct design for ANDV glycoprotein expression (Plan B track)

**Manuscript version 1.0** (methods/results excerpt)  
**Evidence run:** `research/anti-virus/runs/plan_b_exec_20260512T184230Z/`

---

## Abstract

Messenger RNA vaccines against Andes virus require expression constructs that balance codon adaptation to the production host with RNA secondary structure constraints and formulation considerations. Here we report in silico execution of three Plan B workflows on AWS Batch via BioMate: codon optimization for heterologous expression (workflow **10813**), RNA secondary structure prediction (**10721**), and lipid nanoparticle formulation optimization (**12869**). All three runs reached terminal success on Batch with archived outputs on object storage.

---

## Methods

### Codon optimization (workflow 10813)

We submitted `optimize_codons_for_heterologous_expression` through the institutional Nextflow layer with `profile: aws` and executor `awsbatch`. Inputs and outputs are documented in `runs/plan_b_exec_20260512T184230Z/submissions.json` and `EXECUTION_REPORT.md`. Terminal run ID: `e3f044d5-37c5-447d-8941-89fce0ef67e7`; S3 outdir: `s3://biomate-nextflow-work/nextflow/outputs/plan_b_exec_20260512T184230Z/10813_codon/`.

### RNA secondary structure (workflow 10721)

RNA 2D structure prediction was executed similarly (run ID `9f04fe9a-958a-44b7-8573-ac836d982eb2`; duration ~4 min on Batch).

### LNP optimization (workflow 12869)

LNP formulation optimization completed after codon and RNA workflows (run ID `8c29fa67-2d5d-4021-8510-70c0069dd5ed`).

---

## Results

### Codon optimization

The archived `optimize_codons_for_heterologous_expression_results.json` reports successful completion for a **171-nucleotide** DNA input (**57** codons). The optimizer replaced **25** codons (**43.86%**) with host-favored synonymous codons. Original and optimized sequences were written to `original_sequence.txt` and `optimized_sequence.txt` in the task work directory and published under `10813_codon/run/` on S3. Wall time on Batch was **~4 min 11 s** (`poll_results.json`).

### RNA secondary structure

RNA secondary structure prediction succeeded on Batch in **~4 min** (`10721_rna2d`).

### LNP optimization

LNP workflow **12869** succeeded on Batch; versions proof at `proof_12869_lnp_versions.yml`.

---

## Discussion

These Plan B executions establish that the mRNA/LNP workflow ladder is operable on the same BioMate + AWS Batch infrastructure as the epitope and inhibitor tracks. Codon optimization metrics are suitable for Methods supplements in a combined ANDV campaign preprint; they do not, by themselves, demonstrate expression yield or immunogenicity.

---

## Data availability

- Local mirror: `research/anti-virus/runs/plan_b_exec_20260512T184230Z/`
- S3 prefix: `s3://biomate-nextflow-work/nextflow/outputs/plan_b_exec_20260512T184230Z/`
