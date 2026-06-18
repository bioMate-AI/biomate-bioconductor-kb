# Bioconductor data-flow audit + fixes: input, output/viz, findings, fixtures — 2026-06-18

One session, four merged PRs. Started from a slim-image executability validation,
then audited and fixed the Bioconductor data flow end to end: synthetic-fixture
contracts, file input/management, output visualization, and the after-run findings
panel.

## TL;DR — what shipped

| PR | Merge | What |
|----|-------|------|
| #26 | `bafbaec25` | Fixture/workflow read-write format-contract fix (18 fixtures) + scanner + auto-fixer |
| #31 | `498582824` | Findings source provenance, pre-run input format guard, inline RDS preview + **production wiring**, upload `s3_uri` durability |
| #35 | `0bc137d77` | Illustration figures for the Node (Gemini) findings path |

All on `integration/next-phase`. `tsc` 0 errors, vitest **869 passed / 0 failed**,
`py_compile` OK, RDS production validated on a real x86 spot, branch built + run
locally to confirm it boots and the endpoints behave.

---

## 1. Slim-image executability validation (the starting point)

Native x86 spot ran the real-execution harness on a 25-package transcriptomics
sample (44 workflows) in the actual merged `bioc-domain-transcriptomics:3.20-slim`
ECR image. **34/44 produced output**; the 10 hard-fails were **all** the synthetic
fixture writing a format the workflow's reader rejects — not the workflow logic and
not the image. The image + binary lazy-load (Posit PPM + Bioc container-binaries)
work. Full writeup: `docs/20260618_BIOC_SLIM_IMAGE_VALIDATION_AND_FIXTURE_CONTRACT.md`.

## 2. Fixture format-contract (PR #26)

Root cause: auto-generated `<wf>.fixture.R` serialized example data with one format
while the `<wf>.nf` reads it with another (e.g. `saveRDS(selex.sub)` but the workflow
does `read.csv("selex.sub")` → garbage → "duplicate row.names").

- `backend/scripts/scan_fixture_format_mismatch.py` — compares serializer vs reader
  across all 2,471 fixture/workflow pairs: 130 flagged, **21 genuine binary↔text
  crossings** (rest are `writeLines` placeholders).
- `backend/scripts/fix_fixture_rds_contract.py` — pattern-A auto-fixer
  (`write.csv(.df)` → `saveRDS(.obj)`, preserving the typed object `readRDS` expects).
- 18 fixtures repaired (workflow reader = ground truth). Genuine crossings **21 → 3**
  (mbpcr/tidyflowcore/mlp deferred). Proven green on the slim image: aldex2/main,
  aldex2/complex_design_glm, affycontam, linnorm, sdams all `exec_error → ok`.

## 3. The audit (3 parallel reads of the live code)

Concrete, file:line-grounded findings (corrected against the *current* checkout — the
first pass read a stale worktree and overstated several gaps):

**File input / management — solid, two real gaps.** Upload has a 5 GB cap, extension
allowlist (multi-part-aware `.endsWith` for `.fastq.gz`/`.vcf.gz`), rejects unknown
types, UUID naming, presigned direct-S3 path for >100 MB. URL import is protocol-
allowlisted and fetched by Galaxy (no Node OOM). The bioc executor's
`_build_bioc_entry_wrapper` → `_resolve_read_filename` already stages a user file
under the literal name the workflow reads. Gaps: (a) no *content* validation, (b)
`s3_uri` durability.

**Output / visualization — one big bioc gap.** PDF/PNG/CSV render fine, but `.rds`
(the bioc primary output type) was an opaque "Open in RStudio" blob. The QC report
builder is CryoEM-shaped/JSON-only, but bioc QC already flows through the DB
`step_metadata` path, so that was a non-issue. "nextflow" branding leaks are internal
(server→Galaxy calls + S3 keys), not user-visible.

**Findings panel — grounded but unsourced + unillustrated.** Numbers are hallucination-
guarded (every value must appear verbatim in the outputs), but the prompt said *"Do NOT
include citations"* and the code did `delete parsed.citations`, leaving the "Supporting
Literature" UI structurally empty and every metric unattributed. Figures only came from
the Python analyzer (VCF) path.

## 4. Fixes (PR #31 + PR #35)

**Findings source provenance (PR #31).** `GET /findings` prompt now requires a
`source_file` per key_result, validated against the actually-sampled filenames
(hallucinated names dropped); `findings-card.tsx` renders a Source column;
`_build_figures_from_key_results` carries a shared `source_file` onto figures;
`AfterRunReport` shows a "from <file>" caption. Fabricated literature citations are
still blocked — provenance is grounded, not LLM-invented PMIDs.

**Pre-run input format guard (PR #31).** `_assert_staged_input_format` in
`nextflow_executor.py`: HTTP 422 at submit when a workflow will `readRDS` an input but
the content is plain text (the costly `.rds`-expected-but-text mismatch). Real RDS
(gzip/bzip2/xz/uncompressed headers) passes; only `.rds`/`.rdata` destinations are
checked → no false positives. Runs outside the staging try/except so the 422 surfaces.

**Inline RDS preview + production (PR #31).** `step-output-preview.tsx` `RObjectPreview`
fetches a `<name>.rds.json` sidecar and renders class/dim/assays/reductions/colData
inline (graceful RStudio fallback). The sidecar is produced by a `BIOMATE_RDS_INTROSPECT`
process added to the bioc entry-wrapper generator — gated on `emit: objects`, chained off
`.out.objects`, Groovy `'''` literal (no `$`-interp), tryCatch can't fail the run, and it
installs the workflow's own `.bm_deps` first so S4 classes (DESeqDataSet/aldex.clr)
reconstruct. **Correction to an earlier deferral:** a second process is SAFE — outputs
reach S3 via the Batch task's own work-dir `aws s3 cp`, not publishDir (the head-JVM CRT
crash path), so this is a one-place change, not a 2,400-file epilogue. Validated on x86
spot: aldex2 → `{"class":"aldex.clr",...}`.

**Upload `s3_uri` durability (PR #31).** The durable S3 reference lived only in the
in-memory `uploadedFileRegistry`; the Redis-backed session stored `file_path` (host-
local) but not `s3_uri`, and `/api/datasets/session` never surfaced it — so a restart
between upload and run left a re-selected upload unreachable from Batch. Fixed: persist
`s3_uri` in the session, surface it, and prefer it in the browser (matching HistoryTab).

**Findings illustration figures (PR #35).** Generic bioc CSV outputs hit the Node Gemini
findings path, which produced a table but no charts. `buildFiguresFromKeyResults`
(`frontend/server/findings-figures.ts`, a TS port of `_build_figures_from_key_results`,
side-effect-free for unit-testing) projects the grounded key_results into qc/composition/
bars figures, each inheriting `source_file`. 6 unit tests.

## 5. Testing

- Static/unit: `tsc` 0 errors; vitest 869 passed / 0 failed (incl. 2 RDS-preview + 6
  figures tests); `py_compile` OK.
- RDS production: end-to-end on a real x86 spot (ARM laptop can't run amd64 bioc images
  natively).
- Local runtime: built + ran the branch on `:5001` against the real dev DB/Galaxy —
  boots clean, login/upload/session work, `/api/datasets/session` surfaces the new
  `s3_uri` field.

## 6. Open (need real infra, not the local ARM box)

- Live x86 bioc run to *see* the findings figures + RDS card render in the actual UI.
- Non-null `s3_uri` round-trip (the dev box `.env` AWS key is `InvalidAccessKeyId`;
  `_uploadFileToS3` is pre-existing/unchanged).
- 3 deferred fixture crossings (mbpcr `.RData` / tidyflowcore real-flowSet / mlp
  `readLines`).
- Annotation-DB provisioning for the annotation-dependent workflow class (hg19 TxDb/
  BSgenome/org.*.db) — separate known issue.
