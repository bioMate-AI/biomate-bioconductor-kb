# Reviewed experience preparation

`prepare_episodes.py INPUT.jsonl NEW_OUTPUT_DIRECTORY` validates review metadata and exports grouped train/dev/test JSONL. It makes no model calls and does not establish scientific correctness itself.

This pipeline is for the main BioMate assistant. IND/regulatory drafting and audit tasks T22/T23 are explicitly rejected.

Each input record needs:

- A catalog `task_id` for a BioMate task other than T22/T23.
- Unique `record_id`; nonempty list `source_groups` connecting every source incident, document family, study and augmentation parent.
- `training_rights: "approved"`, `review_status: "accepted"`, `context_complete: true`.
- `application_commit`, `prompt_sha256`, complete `messages` ending in the desired assistant completion. Preserve tool calls, IDs, observations and schemas in the record.
- Nonempty `verifier_evidence` list with `passed: true` and an accessible `evidence_ref` for every check. Reviewer must actually inspect this evidence.
- Optional frozen `split`: train/dev/test. Pass earlier manifest assignments with subsequent batches to prevent split drift.

Records sharing source groups or exact message content are joined transitively before splitting. Conflicting assigned splits fail the job. Exact duplicates are removed. The output retains metadata for audit; adapt the training collator to supervise only assistant tokens. Counts are not guaranteed to match desired proportions on small datasets.

This is a first ingestion gate, not a general trace schema validator or semantic deduplicator. Scientific validity, complete tool trajectories, correct episode/run IDs, rights and near-duplicate ancestry still require review. Do not label raw session-associated execution results as episode outcomes. The legacy extractor now marks exports as unverified candidates unless an exact run link is supplied and never fabricates an assistant response.

Offline checks: `python3 -m unittest discover -s evaluation/local_trial -p test_prepare_episodes.py`.

No real episodes have been exported or used to train a model in this implementation session.
