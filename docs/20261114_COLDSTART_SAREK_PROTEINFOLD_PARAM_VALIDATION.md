# Coldstart Batch B — sarek / proteinfold param validation

**Date:** 2026-11-14  
**Cases:** `analysis-domain-gen-0`, `analysis-validated-workflows-2` (nf-core/sarek); `design-fold-complex-pep-0/2` (nf-core/proteinfold)  
**Symptom:** Nextflow `Validation of pipeline parameters failed` (honest fail, no silent soft-pass)

---

## Root cause (class)

Cold-start attaches real demo files, but launch params were not schema-valid for the **executed** nf-core pipelines:

| Workflow | What failed | Why |
|----------|-------------|-----|
| **sarek** | `params.input` samplesheet | Fixture `sequencing_samples.csv` used columns `sample,fastq_1,fastq_2,reference` — nf-core requires `patient,sample,…,status,…,fastq_1,fastq_2`. Relative FASTQ basenames also fail nf-schema `exists:true` because chat uploads land under distinct S3 prefixes. |
| **proteinfold** | required `input` | Real pipeline requires a CSV (`id,fasta`). Stub/UI emphasized `sequence`; peptide bundle had no samplesheet; FASTAs never became a valid `--input`. |

Clarify asking for sarek `step` was a symptom of stub/schema mismatch (step is required-with-default in real schema); not the validation root cause.

---

## Fix (rule-first, no harness workaround)

1. **Fixtures**
   - `sequencing_samples.csv` → nf-core sarek columns (`patient,sample,sex,status,lane,fastq_1,fastq_2`).
   - New `proteinfold_samplesheet.csv` (`id,fasta` → `1BXL.fasta`) added to peptides cold-start bundle.

2. **Resolved samplesheet at bind time** (`frontend/shared/attachment-binding.ts`)
   - `buildResolvedNfcoreInputSamplesheet(workflow, attachedFiles)` rebuilds `input` as an inline CSV whose path cells are co-attached `s3://` / dataset refs.
   - Wired in `galaxy-assistant.ts` after attachment bind (also writes `inline_parameters` / `parameters` because `input` is often executor-owned `data_inputs` only).

3. **Materialize inline CSV → S3 at execute** (`nextflow_executor.py`)
   - `_materialize_inline_samplesheets` uploads the multiline CSV before nf-schema `validateParameters` (schema types `input` as file-path).

4. **Schema-aligned stubs + local `nextflow_schema.json`** under `backend/biomni_workflows/nfcore/{sarek,proteinfold}/` so the panel/gate match real required params (`input`/`step`/`tools`/`fasta` / proteinfold `input`+`mode`).

5. **Rule prefill** (`_rule_based_param_inference`)
   - Tumor+normal / sequencing_samples / clinically-relevant variant prose → `tools=mutect2`.
   - Complex/peptide-bound / alphafold prose → `mode=alphafold2`, `alphafold2_model_preset=multimer` when applicable.
   - Cold-start prepared context documents GRCh37 `--fasta` + mutect2 / proteinfold samplesheet.

---

## Verify

```bash
# Unit
cd frontend && npx vitest run shared/attachment-binding.test.ts \
  client/src/components/cold-start-demo-catalog.test.ts

# Deep coldstart (flocked; after sync to DEV)
cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
  BIOMATE_DEEP_FILTER='analysis-domain-gen-0|analysis-validated-workflows-2|design-fold-complex-pep-0|design-fold-complex-pep-2' \
  ./e2e/run_coldstart_deep.sh
```

Expect: Confirm launches with schema-valid `input`; no immediate “Validation of pipeline parameters failed”. Downstream Batch runtime (image/weights/GPU) may still fail for other reasons — that is a separate class.

---

## Remaining gaps

- Full sarek/proteinfold Batch success still depends on reference/weights/GPU and path staging beyond param validation.
- `design-fold-complex-pep-1` was `NO_LAUNCH` (routing/UX) — out of this batch.
- If a parallel writer reverts `sequencing_samples.csv`, the bind-time rebuild still covers launch as long as the four FASTQs are attached.
