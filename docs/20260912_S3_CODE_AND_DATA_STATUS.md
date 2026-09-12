# S3 code and data continuation — 12 September 2026

Read access to the existing dataset and code bucket is verified. Three compared cloud modules differ from the latest committed fixes: train_czi_irm.py, load_czi_perturbseq.py, and czi_irm_head.py.

Prepared release: commit `68ad377eee7cba53dae8338bde8ea27842e8b481`, 214 committed research files, 574,472-byte compressed archive. The checksum/file manifest is in `20260912_s3_continuation/release_manifest.json`. The archive is `/tmp/immune_code_68ad377eee7c.tar.gz`. Uncommitted files, model weights, datasets and runtime caches are excluded.

Verified release destination:
`s3://knowledge-datasets-1759951976/immune_llm_baseline/releases/68ad377eee7cba53dae8338bde8ea27842e8b481/`

Uploaded `code.tar.gz` and `manifest.json` after explicit user approval. Both objects were created conditionally and their complete readback SHA256 checksums matched the local payloads. The existing `immune_llm_baseline/code/` prefix was not modified. Verification is recorded in `20260912_s3_continuation/upload_verification.json`. Automatic review initially required explicit authorization; the user subsequently approved this exact upload.

Data findings:

- `GWCD4i.DE_stats.by_donors.h5mu` contains six donor-pair modalities, not six independent donors. Source README confirms donor-pair eligibility. Randomly splitting these modalities could share a donor across folds.
- `GWCD4i.pseudobulk_merged.h5ad` contains 278,684 guide/donor/condition profiles and 18,129 genes. Four donor IDs and three culture conditions are explicit.
- Non-targeting controls passing `keep_for_DE` exist in every donor-condition combination: 720–972 pseudobulk profiles per combination. These counts describe profiles, not independent biological replicates.
- README describes X as sums of UMI counts. Count values have not yet been extracted or independently checked; metadata availability does not establish model performance.

Next data step: extract only non-targeting controls and a frozen perturbation panel, validate counts, aggregate control baseline expression by donor/condition, and define a donor-separated evaluation before training. Pairwise DE outputs must not be mistaken for independent donor labels. Perturbed profiles must not be used as baseline-state features.

Read-only inspection evidence is in `20260912_s3_continuation/dataset_schema.json` and `control_feasibility.json`. No large matrix download or cloud training instance was started.
