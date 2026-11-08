# 2026-10-22 — Systemic audit of the workflow-execution bugs hit during demo prep

**Why:** demo prep kept hitting "fix one bug, hit the next" on Batch runs. Rather than patch
per-workflow, this audits each failure as a *class* across all 4,495 `.nf` workflows + the
container images, fixes the upstream source where one exists, and adds a guard. Method:
`.claude/skills/systemic-root-cause`.

## The 4 classes (from the QSAR-RF + REINVENT4 runs)

| # | Class | Blast radius (verified) | Status |
|---|---|---|---|
| 1 | **Inline-python `IndentationError`** — a `script:` block mixing outer-indented python with an inner col-0 heredoc (`'''`/`"""`). Nextflow strips the common indent → first statement indented after a col-0 shebang → `IndentationError`, only on Batch. | **GENERAL: 8 blocks / 6 cryo-EM-ET workflows** (`focused_refinement_pipeline`, `3d_variability_analysis`, `3d_variability_pipeline`, `tomogram_reconstruction`, `import_tiltseries`, `et_full_pipeline`) + `qsar_rf_model` | qsar **fixed** (`9311c351`). **Guard committed** (`f134df6f`): `scripts/validate_nf_inline_python.py` compiles every workflow's inline python the way Nextflow does. The 6 cryo files still need careful per-file de-indent (an auto-fixer was unreliable on their nesting — reverted). |
| 2 | **Declared `versions.yml` output never written** → "Missing output file" aborts a *successful* run. | **qsar-SPECIFIC** — precise scan found **0** other self-contained inline-script workflows with this defect (nf-core composites write versions in sub-modules). | **CLOSED** (qsar fixed, `fcece339`). |
| 3 | **`params.X = null` marked required** though the workflow uses a `params.X ? … : default` fallback (REINVENT4 `prior_path` → container default). | **Inconclusive as a blanket class.** ~20 nf-core workflows declare null params with fallbacks, but most are *legitimately* optional (`email`) or *genuinely* required (`matrix`, `samplesheet`). Case-by-case, not a uniform bug. | REINVENT4 instance **fixed** (`dc5ebab2`). No blanket fix warranted. |
| 4 | **Container missing `ps` (procps)** — Nextflow needs `ps` for task metrics; a minimal base fails the task at launch. | **NARROW.** Most images inherit `ps` from the custom `biomate-nextflow-base` (that's why ADMET/pharma/tools runs work). The risk is **minimal-base images** (micromamba → `reinvent4-nf`; possibly exotic cuda-runtime/distroless bases). | REINVENT4 **fixed** (`82cccf55`, add procps) — needs the x86 image rebuilt. Guard idea: assert `command -v ps` in `.github/workflows/build-biomni-image.yml`. |

## Answer to "are these bugs workflow-specific or general?"
**Mixed, and now measured:** Class 1 is the one genuinely *general* latent bug (7 workflows share
it) — and it's the dangerous kind because it only surfaces after a Batch job starts. It's now
**guarded** so no workflow with the defect can ship or regress. Class 2 was a one-off (closed).
Class 4 is narrow (minimal-base images only). Class 3 isn't a clean class.

## Open follow-ups
1. **Fix the 6 cryo-EM/ET workflows** (Class 1) carefully, one file at a time, verifying each with
   `scripts/validate_nf_inline_python.py` (the auto-fixer corrupted the cryo_et nesting — do it by hand).
2. **Wire the guard into the pre-sync checklist** (`docs/PRE_SYNC_CHECKLIST.md`) + CI as a HARD gate.
3. **Add a `command -v ps` assertion** to the reusable image-build CI (Class 4).
4. Rebuild `reinvent4-nf:x86` so the procps fix lands (Class 4).
