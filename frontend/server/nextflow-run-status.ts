/**
 * Read-time reconciliation helper for a single (non-chain) Nextflow run.
 *
 * The stuck-'running' bug: the run-status endpoint promotes a live Nextflow
 * terminal state into the BioMate run status, but historically handled only
 * 'succeeded' / 'failed' / 'error'. A run whose subprocess is SIGNAL-KILLED
 * reports Nextflow state 'interrupted' (the launching gunicorn worker died
 * mid-run, or a container restart), which fell through → the run stuck on
 * 'running' forever.
 *
 * `isOrphanInterrupt` decides when an 'interrupted' Nextflow state should be
 * finalized to 'failed' at read time. It is deliberately conservative:
 *
 *   - Only when the BioMate status is still 'running' / 'configuring'. A
 *     DELIBERATE pause (QC gate) or cancel also signal-kills the process, but
 *     then the status is 'paused' / 'cancelled' and must be preserved (a paused
 *     run is resumable; flipping it to failed would kill Resume).
 *   - Only for LOCAL (non-batch) runs, where the subprocess IS the execution.
 *     For an AWS Batch run the local driver can be interrupted while the Batch
 *     job keeps running, so those are left to the completion poller's
 *     describe_jobs check (authoritative Batch verdict) rather than flipped
 *     prematurely here.
 */
export function isOrphanInterrupt(
  nfState: string,
  currentStatus: string,
  isBatch: boolean | undefined,
): boolean {
  return (
    nfState === "interrupted" &&
    (currentStatus === "running" || currentStatus === "configuring") &&
    isBatch === false
  );
}
