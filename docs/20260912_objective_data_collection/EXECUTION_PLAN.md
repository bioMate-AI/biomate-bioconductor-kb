# Objective data — execution plan (post-extraction)

Decisions taken: ImmPort will be accessed with user-supplied credentials; proceed
stepwise and execute. Every step ends training-ineligible until the admission gate
(matrix join + overlap dedup + human sign-off) is cleared.

## Steps

| # | Step | Blocked on | Acceptance criteria | State |
|---|------|-----------|---------------------|-------|
| 1 | Extract GSE35455 + GSE113156 expression matrices from local SOFT, join to labels | nothing | matrix + QC per GSE | **DONE w/ correction** — GSE35455 built (`raw/GSE35455_afterbefore_matrix.tsv`, 29,736×112) but **demoted**: dye-swap replicates fail per-patient QC (median r=−0.02). GSE113156 matrix NOT in SOFT → needs download. |
| 1b | Download GSE113156 supplementary + join | public download | matrix joined to 6-subject labels | **DONE** — RNA-seq counts 20,812 genes × 22 samples, 11 complete w0/w24 pairs, healthy libsizes (`raw/GSE113156_counts_matrix.tsv`). Strongest local cohort; external-test only (small n). |
| 2 | Overlap/dedup vs existing pretraining/KG/text inventory | locate inventory | per-accession verdict | **blocked** — need inventory location from you |
| 3 | ImmPort SDY1490 (iWITH) participant-level download | **user credentials** | token exchange OK; withdrawal/visit tables hashed | **fetcher ready** (`fetch_immport.py`, fails safe) — waiting on creds (you said not yet) |
| 4 | Druggability: ChEMBL (done) + BindingDB (S3) | S3 access to `BindingDB_All_202409.tsv.gz` | tractability labels + family split | **PARTIAL** — ChEMBL done: 20 immune targets, modality split (small-mol vs biologic) in `druggability_chembl.json`. BindingDB **blocked**: S3 bucket not accessible (no creds). |
| 5 | Combination benefit: DrugComb dose matrices | public download | dose matrices + controls | **blocked** — drugcomb.org + api.drugcomb.org both unreachable (timeout), not an access issue on our side |
| 6 | Fold all frozen splits into one objective evaluation register + refresh AUDIT | steps 1–5 | one register per objective | pending remaining lanes |

## Guardrails carried forward
- Aggregate trial outcomes never expanded to per-patient examples.
- Held-out patients/trials never enter train or retrieval.
- No optimization on any label until the gate clears.
