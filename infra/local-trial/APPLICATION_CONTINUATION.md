# BioMate application trial continuation

This package is prepared locally; preparation is not a successful remote deployment.
The former worker was scheduled to terminate at 2026-09-12 20:20:03 UTC.
Confirm its state before trying to connect. Remote operations are currently blocked by
the approval-service usage limit; do not bypass that rejection through another tool.

## Recovery order

1. When remote access is available again, inspect the previous worker and latest S3
   progress receipt. If terminated, provision only the already-authorized Spot/CPU
   class with a termination deadline and restore the verified model and knowledge
   manifests recorded in `CHECKPOINTS.md` and `results/`.
2. Apply the latest scoped workspace bundle, including the knowledge-query route,
   compact intent prompt, base-table migration, and application launchers. The older
   S3 source bundle does not contain these changes. Preserve the recovered source
   base and apply `implementation.patch` only after `git apply --check` succeeds.
3. Prepare the isolated application dependencies and databases as described by
   `prepare-application.sh` and the worker launchers. Do not reuse production users,
   environment files, or database connections. Resolve all downloads before testing
   external-network denial.
4. After the five model shards have passed the manifest's size/hash verification,
   install `serve-current-model.conf` as the local-model service drop-in. Its direct
   launcher avoids repeating conversion and upload on each inference restart.
   Restart the model to discard any abandoned oversized request. Keep loopback
   binding and the existing termination/backup timers.
5. Install the two supplied acceptance `.service` files in the worker's systemd
   service directory and reload systemd. They are persistent one-shot definitions:
   a failed or stopped test remains restartable, unlike the earlier transient unit.
   Run the HTTP check and FastQC CPU check independently. The HTTP check waits for
   frontend, backend and model readiness; inspect its JSON report, not merely the
   service start result. It can take several minutes on CPU.
6. Register `fastqc.xml` in the isolated Galaxy tool configuration. Upload the
   generated synthetic FASTQ into an isolated trial history, invoke a workflow
   containing this tool, and retrieve both output datasets. Run `verify_fastqc.py`
   against those downloaded outputs and retain the history, workflow, invocation,
   job and dataset IDs. The standalone CPU check is only a prerequisite; it does
   not establish that Galaxy or the LLM invoked the tool correctly.
7. Run chat/workflow authorization and external-model-network-denial checks, then
   publish and restore-check the updated source and evidence bundles. Preserve
   failed runs as well as successful reruns. Record the client hardware and measured
   latency before describing the deployment as client-ready.

## Local package and independent checks

```sh
python3 -m unittest discover -s infra/local-trial -p 'test_verify_fastqc.py'
python3 infra/local-trial/backup_workspace.py --local-bundle /private/tmp/biomate-trial-bundle-UNIQUE
```

On a worker with FastQC installed:

```sh
python3 /opt/biomate-trial/evaluate_fastqc.py --output /opt/biomate-trial/fastqc-evaluation
python3 /opt/biomate-trial/verify_fastqc.py DOWNLOADED_REPORT.html DOWNLOADED_ARCHIVE.zip
```

The fixture contains 100 reads of length 100 and 50% GC. It is deliberately
repetitive: QC module failures must be displayed, not erased to make the test pass.
Expected counts verify artifact correctness; they are not scientific validation of
the biological workflow or model. No training result is implied by these checks.
