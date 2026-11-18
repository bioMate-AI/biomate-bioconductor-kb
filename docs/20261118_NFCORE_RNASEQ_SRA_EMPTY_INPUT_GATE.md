# nf-core reads-samplesheet pipelines: auto-wire SRA/ENA accession → `--input` (SRA rnaseq fix)

**Date:** 2026-11-18
**Scope:** `frontend/server/routes.ts` `/api/workflows/execute` gate

## Live bug (verified on dev)
End-to-end UI test on `dev-public.biomate.ai` (as `drugtest@biomate.dev`):

- "Run nf-core/rnaseq on SRR1039508" generated a correct-looking card (*"Input: SRR1039508 … the workflow will fetch the FASTQ reads automatically"*) and **launched a real Batch run that FAILED in ~90s** at `Validation of pipeline parameters failed!`.
- The run's saved `params.json` (run `b4cd9246`): **`input: null, fasta: null, gtf: null, genome: null`**.
- The submitted `workflowDefinition.required_params` was **`[]`** — `input` was not present as a param, and the SRA accession never reached the launch payload. Two older Nov-16 runs failed identically (the Run-Manager "Need Attention" pile).

## Why the many GEO fixes didn't cover it
The existing accession auto-chain handles **GEO → `geo_data_connector` → differential-expression** (the DE guard in the same file). nf-core/rnaseq is **not** a DE workflow and an **SRA accession is not GEO** — sequencing reads go `SRA → nf-core/fetchngs → FASTQ + samplesheet → alignment`, a different flow with no equivalent wiring. So the SRA→rnaseq path launched empty.

## Root cause
The backend **already has** the machinery: `_accession_chain_thread` → `_run_fetchngs_prefetch` turns a *sequencing accession present in the launch params* into a fetchngs samplesheet before the main run. It never fired because **the accession never reached the launch params** — it lived only in the chat text / card description, not in `workflowDefinition.parameters`. And no reference genome was set.

## Fix (this change)
In the execute gate, for nf-core **reads-samplesheet** pipelines (`rnaseq|sarek|scrnaseq|atacseq|chipseq|cutandrun|methylseq|rnafusion|smrnaseq|nanoseq|taxprofiler|ampliseq|viralrecon|rnasplice`; DE excluded) launched with an unbound `--input`:

1. **Find the SRA/ENA accession** in the request (params / inputs / inline_parameters / name / description — same haystack the DE guard uses).
2. **Auto-wire it into `input`** (`request.workflowDefinition.parameters.input = acc`) so the backend accession-chain runs fetchngs → samplesheet → this pipeline's `--input`.
3. **Pick an organism-correct reference genome** by looking up the accession's `scientific_name` from **ENA** (`filereport` API) — never guessed. Human→GRCh38, mouse→GRCm38 (exact iGenomes NCBI paths a working rnaseq run uses). Any other organism (or ENA miss) **blocks and asks for a reference** rather than align to the wrong genome.
4. If **no accession** is present at all, block with an actionable "needs a samplesheet" message (no compute burned).

Only fires when `input` is unbound → **no regression** on runs with a bound samplesheet. `tsc --noEmit` clean; frontend `vitest` passes (2 failures are pre-existing `ENOENT` on backend `.py` files absent in this sparse deploy worktree).

## Verification plan (on dev, post-deploy)
Re-run "Run nf-core/rnaseq on SRR1039508" and read the new run's `params.json`: expect `input` = the accession (then replaced by the fetchngs samplesheet) and `fasta`/`gtf` = GRCh38, and the run to progress **past** nf-schema validation into `fetching_accessions` → fetchngs → running (instead of failing at ~90s).
