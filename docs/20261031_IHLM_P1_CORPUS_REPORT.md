# IH-LM P1 corpus build — STOPPED (2026-10-28 evening CDT)
**STOPPED: pivot to fine-tuning an open-weight pretrained backbone; corpus may serve later continued pretraining/fine-tuning.** Owner decision relayed by the coordinator: no from-scratch LLM pretraining. No corpus was built, no instance was launched by this task, no download was made, spend = USD 0. Existing files and S3 objects were left untouched. The plan it would have executed remains `docs/20261030_IHLM_PRETRAINING_PLAN_P1.md` (§1 corpus, union fold filter, CycPeptMPDB exclusion); the source list, sizes and licences are in `docs/20261030_PEPTIDE_PRETRAINING_CORPUS_SURVEY.md` (sizes there are as read by that survey; I did not re-verify them).

## Inventory of what already exists (excavation only; nothing re-measured)
| item | where | size | note |
|---|---|---|---|
| P0 corpus filter outputs (2.88 M ChEMBL-derived P0 corpus vs held-out compounds; union removed 8,983 = 0.312 %) | local `research/guangzhou_all_atom/cyclic_llm/v4_eval/filter_full/{filter_report.json, progress.log, removed_union.npy}`; S3 `cyclic_peptide/v5/filter/` (6 objects, 11.0 MiB) and `v5/filter2/` (51 objects, 761.6 MiB; contents not listed here) | small / 762 MiB | figures from the P1 plan §9; the corpus text itself was not located in this pass |
| P0 pretrain checkpoint + vocab | S3 `cyclic_peptide/allatom/pretrain/` (ckpt.pt 291.7 MiB, vocab.json 2.1 KiB, pretrain.json) | 292 MiB | 25.5 M-parameter atom LM, P0 only |
| CycPeptMPDB table (held-out oracle; exclude from any pretraining) | S3 `allatom/data/CycPeptMPDB_Peptide_All.csv` (18.2 MiB); local `research/guangzhou_all_atom/data/raw/` | 18.2 MiB | CC BY 4.0 per the survey (site SSL error; licence from the paper) |
| CREMP | local `research/guangzhou_all_atom/prep_cremp_dataset.py`; scratchpad `cremp_summary.csv` | script + summary only | the full CREMP download was not found on disk or S3 |
| PeptideCLM-2 / PepMSND metadata | local `data/source_metadata/*.json`, `data/raw/peptideclm2_pepmsnd/` | small | metadata, not the 10 M generated pool |
| Local data dirs | `research/guangzhou_all_atom/data/raw` 98 MB, `processed` 8.1 MB, `display` (NGS display tables) | — | none of these is a pretraining corpus |

## Not found (missing): Macrocycle-DB, NPAtlas, COCONUT, NORINE, DBAASP, PeptideCLM Zenodo generated pool, PDB CCD peptide ligands, the Stage B 884-complex manifest as a corpus input, and the 2.87 M ChEMBL SMILES file itself (only filter outputs/checkpoint located). Not searched beyond S3 `cyclic_peptide/`, the repo and a filename search of local disk.

## Licence flags (from the survey; unverified at primary sources where noted there)
NPAtlas CC BY-NC 4.0; Peptipedia CC BY-NC-ND / ODbL non-commercial; ChEMBL CC BY-SA 3.0 (share-alike on derived databases); COCONUT CC0 on the site vs CC BY in the paper (use CC BY); Macrocycle-DB licence not stated; CycPeptMPDB CC BY 4.0 per the paper; PeptideCLM data CC BY 4.0, weights MIT; DBAASP/NORINE/APD licences unverified.

## Spend: USD 0. Instances launched by this task: none.
