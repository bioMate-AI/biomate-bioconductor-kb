# Dev scientific readiness PR sync and test log

## Scope and deployment review

Requested on November 7, 2026, America/Chicago: create a PR, sync the local changes to dev, and test the deployed platform. The live frontend identifies commit `7c030334b439df2ecc7d384e7c2812c1a59c843f`, the head of PR 328 (`codex/zh-en-ui-parity`). The new fixes are based on that deployed commit, not the older active shared-checkout HEAD. Existing language, project-chat and report fixes must remain intact.

The shared checkout contains unrelated on-prem changes. Only the explicit scientific-readiness patch and its tests/documentation are included. The shared branch and index must not change. The application catalogue and live Galaxy user database are not replaced. No IAM, network, queue-capacity or credential change is required.

The patch requires the existing Galaxy runtime, workflow catalogue and workflow-tools image. It adds no package dependency. Target requests can provide a full disease name, which is resolved against Open Targets before ranking. Invalid or conflicting identifiers must not produce a successful evidence-backed answer. Peptide-property requests must not force a protein-folding card merely because they contain a sequence. The physicochemical workflow must produce ethanol reference descriptors, publish its CSV, reject invalid SMILES and omit unsupported logD/pKa claims.

Before syncing, verify exact frontend source tests and backend import compatibility. Build the frontend while the current container continues serving. Preserve the current runtime configuration and retain the previous frontend container plus backups of the four changed backend/workflow files. Apply only those files, restart the Galaxy master to avoid preloaded stale code, and verify health and deployed hashes. If readiness checks fail, restore the previous files/container rather than recording the old application as a successful new deployment.

## Required post deployment tests

1. Confirm the public frontend build identifier and the three backend file hashes match the reviewed release.
2. Repeat the consolidated online ADMET, peptide-property and EGFR/NSCLC cases with one fixture login and one temporary project. Verify real structured results and no automatic dispatch.
3. Execute the small physicochemical fixture through the online platform. Download and inspect the actual CSV/JSON, including ethanol molecular weight, atom counts, QED and correctly named molar refractivity.
4. Test invalid SMILES without accepting a successful scientific result. Do not bypass safety gates or substitute demonstration data.
5. Record failures and cleanup outcomes, and update the team acceptance handoff without treating local tests or skipped tests as live scientific qualification.

## Execution record

PR: https://github.com/bioMate-AI/biomate/pull/335. Initial code commit: `97528d44ca33afe767c3472599c665283cd404f2`, based on the deployed PR 328 head. Creating the branch through an isolated Git index preserved the shared index and active branch.

The exact local release was exported to `/private/tmp/biomate-dev-release.ukBtS0`. Its TypeScript check passed; 31 focused frontend tests passed, including preserved response-language behavior; 26 routing/resolver tests passed; and all 12 target-handler regression tests passed. The handler suite's optional validation-plan path reports that this export has no runtime catalogue; these unit tests are not a validation-plan scientific qualification.

The dev host preflight showed 18 GiB available disk and approximately 10 GiB available memory, with the existing frontend, Galaxy, remote connector and PostgreSQL healthy. The three deployed backend fingerprints matched the intended baseline. No old container or global build cache is pruned for this sync.

The one-shot audited sync script is `docs/qa/20261107-dev-online-readiness/sync_reviewed_release.py`. It verifies a release manifest and baseline, builds before changing services, retains the previous frontend container, backs up exactly three Python modules and one workflow, preserves the effective frontend environment without logging credentials, restarts the preloaded Galaxy master and verifies health plus build identity. It uses the supported sync script's lock and rolls back its own changes if the gate fails. It deliberately does not replace either database, modify credentials, run migrations, change queues or deploy the unrelated on-prem work.

Current status: PR open; exact-release pre-sync tests passed; deployment and live retests pending. Not ready for teammate acceptance.
