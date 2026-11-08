# Append-only local run-history recovery — 2026-11-07

After the first dev sync completed successfully, the two missing local run-history trees were recovered from the retained pre-sync rollback image into the current live container.

The complete on-host archive was validated before any live write: 2 run directories, 22 regular files, 99,930 bytes. The validator rejected absolute/traversal paths, symlinks, hard links, special members, duplicate paths and directory/file collisions. Synthetic validation checks passed before execution.

Recovery ran as Galaxy UID 1000. Run directories were created exclusively, with whole-run skipping for any existing destination. Files used exclusive creation and no-follow flags; no existing live path was overwritten. Ordinary permission bits and timestamps were preserved, without setuid/setgid bits. All 22 restored files passed SHA-256 verification. Historical directory count rose from 0 to 2; no run was skipped.

Only aggregate evidence left the instance. No historical filenames or file contents were printed or exported. The original rollback image was retained; only the operation's private staging archive was removed after successful verification. There was no application restart, database modification, S3 modification or workflow rerun.

Evidence: `docs/qa/20261107-hospital-readiness/run-history-recovery-aggregate.json`; local execution log `/tmp/biomate-hospital-audit/run-history-recovery.log`. SSM completed successfully.

This restores local history trees, not deleted chat/run database records. Their associations and reopening behavior are separate API/UI acceptance checks. Removing the destructive sync cleanup preserves these trees for the planned follow-up sync without container recreation. `/tmp` storage is still ephemeral across a future container replacement; this recovery does not introduce a new durable mount or claim otherwise.

Recovery snapshot retention: the original image was verified and tagged
`biomate-galaxy-dev:pre-history-recovery-20261108`, protecting its recovery source
when a later sync retags the ordinary rollback image. No images were pruned.
Aggregate evidence: `docs/qa/20261107-hospital-readiness/recovery-snapshot-hold-tag.json`.

The current `/tmp/nextflow_runs` directory is not a persistent Docker mount.
A future container recreation needs a separately reviewed migration to persistent
storage. This does not block the current follow-up sync: no container recreation
is planned, and the destructive sync cleanup has been removed.

Saved-record API verification after the first sync: the dedicated synthetic
Chinese chat reopened unchanged with its project link and two saved messages.
Two owned completed historical runs returned their saved workflow definitions
and canonical Replication records with 197 and 77 outputs respectively, matching
the recorded baseline. Neither run recorded a `chatSessionId`; a run without that
link cannot reconstruct its original conversation. No new execution was started.

The same check found an independent security defect: anonymous requests to the
legacy reproducibility export proxy returned payloads for these owned fixtures,
while the canonical Replication API correctly returned 401. This was escalated
to the parent for an access-control fix before deployment. Evidence contains only
aggregate counts and owned fixture IDs; no file contents or credentials.
