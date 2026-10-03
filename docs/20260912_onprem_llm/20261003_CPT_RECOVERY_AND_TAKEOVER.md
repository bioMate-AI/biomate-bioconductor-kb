# BioMate domain model takeover — 2026-10-03

## Design retained

The October design supersedes the September single-model trial: general model for harness-carried
tasks, domain-pro for domain judgment, with retrieval and verification retained for both.
The concept CPT corpus and domain SFT are the current training path. IND is outside this work.
The on-prem deployment stack is owned by the other workstream and is not being rebuilt here.

## Verified failure, not a completed training run

At takeover, AWS us-west-2 had no running BioMate LLM trainer. The saved small/full_concept
boot log shows the loader failed after 189,645 records: PMC and background rows have different
metadata fields (`topic`, `title`, `chars`). No concept checkpoint was found under the inspected
small/full_concept or med/full_concept prefixes. The 9B boot log ends during dependency installation.

The shell continued after the dataset error into failed merge and SFT, then printed
`SPOT_full_concept_DONE ... rc=0`. This was a false success caused by missing fail-fast handling
and an assignment overwriting the training return code.

The concept composition manifest reports 593,367,127 **approximate** tokens, including 166,724
PMC full-text and 23,562 PMC review entries plus repeated background sources. These are builder
counts, not an independent quality/license/leakage audit. They do not establish a review-only corpus.

## Repairs and validation

- CPT uses a text-only generator with an explicit dataset schema; heterogeneous provenance metadata
  stays in the original corpus. Invalid or blank training text fails with its source line number.
- Trainer exits on a failed stage and preserves the exit status through S3 cleanup.
- Cleanup retains the original checkpoint root after SFT changes the final-artifact directory.
- Training logs are actually written to the path the backup loop uploads.
- Bootstrap failure prevents training, and the worker timeout bounds bootstrap plus training.
- Shell tracing is disabled: previous boot logs exposed provider credentials. New recovery workers
  receive empty teacher API credentials. The old credentials require rotation by their owner;
  they are not copied into this document or new source artifacts.
- Two corpus regression tests and one mocked full-pipeline failure test pass. The latter proves a
  CPT failure never reaches merge, SFT, or final publication. GPU validation remains separate.

## Bounded recovery run

S3 root: `s3://biomate-models-399683337364/biomate-core-local-trial/20260912`.

First recovery worker `i-0d4a89718ac28a4eb` failed because the AMI lacked `python3-venv` and
entered shutdown. Bootstrap now installs it when necessary. No training completed on that worker.

Replacement: `i-0565e90849ec84609`, g6.2xlarge Spot, tag `_concept_recovery2_20261003`.
Price ceiling $1/hour; bootstrap/training timeout 7,200 seconds, followed by shutdown/termination.
EBS and storage charges are additional. Requested stages: 50 CPT steps then 10 SFT steps on
Qwen/Qwen3-4B, sequence 2,048, batch 1, accumulation 4, general replay fraction 0.3.
This is pipeline validation, not the 9B experiment or a customer-ready model.

- Code archive: `code/recovery_20261003_v2.tgz`.
- Corpus: `midtrain_corpus/midtrain_domain_concept.jsonl`.
- SFT: `sft/multitask_sft_concept.jsonl`.
- Logs: `spot_logs/small/full_concept_recovery2_20261003/`.
- Checkpoints: `spot_ckpt/small/full_concept_recovery2_20261003/`.
- Resolved dependencies are saved alongside the logs; current bootstrap version ranges are not a
  reproducible release environment until those versions have been validated and pinned.

## Correct deployment identity

Current pipeline: original weights → CPT adapter → merged `base_domain` → SFT adapter.
The final SFT adapter requires the **exact merged base_domain checkpoint**, not the original
4B/9B checkpoint and certainly not Qwen3-8B. For trial delivery, merge SFT into base_domain and
serve the resulting standalone domain model, with the unmodified general model separately.
This preserves the two-model design without changing the domain training base to fit a stale
launcher default. The current vLLM launcher only scans `regulatory_llm_*`; generic adapter
auto-discovery is not yet implemented there. No IND adapters were modified.

## Offline data work

`BIOMATE_OFFLINE_MODE=1` plus `BIOMATE_CHEMBL_SQLITE=/absolute/path/chembl.db` now enables a
read-only ChEMBL resolver through the existing federated-query seam. It returns exact ID/name/synonym
matches and SMILES/properties, does not invent PubChem IDs, and does not download data at runtime.
Five synthetic-schema/seam tests pass, including network-denial checks. A production ChEMBL database has **not** yet been provisioned or
validated; literature indexing is also still pending. This is not a claim of complete air-gap coverage.

A 100,001-byte sample of `pmc_concept_corpus.jsonl` yielded eight complete records; all contained
only text/source/year/licence, without PMID, PMCID, DOI or URL. Source inspection confirms that the
bulk builder dropped article IDs and the filter dropped remaining metadata. Future builds now retain
article identity, source URI, content digest and source family through filtering and PMC mining;
two filter regression tests pass. Token estimates now count emitted, truncated text. The existing
corpus has not been rewritten, and paper IDs must be recovered upstream before citation-bearing RAG.

## Revised SFT data audit

The exact current S3 concept-SFT file contains 72,397 structurally valid records across 17 tasks.
There are 98 repeated message sequences. None carries explicit `source_family`/`source_groups`
metadata; broad source labels are present. That does not prove leakage, but it prevents certification
of source-family independence from this export alone. Upstream split manifests must be reconciled.
Evidence may be embedded in prompts, so absent evidence metadata is not evidence-free training.
Counts and the file SHA-256 are in `20261003_CONCEPT_SFT_STRUCTURAL_AUDIT.json`.

The upstream Qwen3-4B tokenizer template lacks generation markers. Current
[TRL documents automatic Qwen3 template patching for assistant-only loss](https://huggingface.co/docs/trl/en/sft_trainer).
The installed trainer's actual nonzero assistant masks still need verification; documentation alone
does not certify this dataset or the merged-base tokenizer.

## Next gates

1. Confirm actual optimizer steps, saved checkpoints and S3 restoration for the recovery run.
2. Verify SFT assistant-token masking and source-family holdout separation on the revised dataset.
3. Pin the successful dependency/model revisions; launch the 9B concept experiment from that recipe.
4. Compare base versus domain-pro with identical retrieval, execution graders for runnable tasks,
   and knowledge/judgment metrics. Do not use routing gains or closed-book recall as CPT proof.
5. Provision and validate offline compound/literature evidence with source provenance, then perform
   the customer trial against the revised on-prem harness.
