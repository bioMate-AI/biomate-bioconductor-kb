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

## Scoped deployment result

Deployed commit: `4dde598fd1d78fd77e0833e0da5f0ea4c084f1b9`. The public `/build-info.json` independently returns this identifier. SSM sync command `c5641bcd-76e8-4df0-b24b-12947aabff68` completed successfully and recorded `result=healthy`.

The private release archive was generated from the local Git release, not from a remote checkout or the dirty shared tree. It contained 1,032 manifest-verified source files, was 20,128,901 bytes, and had SHA-256 `7e3f4f22fb85c0f6af6e0210326ab7ae11137ce07adf396759da890db0576dd1`. Transfer object: `s3://biomate-nextflow-work/dev-sync/scientific-readiness/4dde598fd1d78fd77e0833e0da5f0ea4c084f1b9/release.tar.gz`.

The built frontend image ID is `sha256:42e10ad9dcdd8927c849fdce578778871d64f7e0a53d36bb4622d564087c1e46`. Previous frontend container retained: `biomate-dev-frontend-rollback-4dde598fd1d7`. Backups of the four changed runtime files are under the release's `rollback/` directory on dev. The temporary runtime env file was removed after use; no credential values entered the archive or log.

Runtime verification:

| File | SHA-256 |
| --- | --- |
| `ai_assistant.py` | `d786878b46ed588710f7c63e228954074133a96141a1956c9de0b957e6208a9d` |
| `target_id/data_channels.py` | `ad8ec751e5c104ace10ef3ea247c4f1eed3f44e9870d6070fff41fdcca52a773` |
| `target_id_api.py` | `ab0c00cb6b0708ea8ed2372c4b1ef592cdf91870e079a1b7255bda4a9844e32b` |
| Physicochemical workflow `main.nf` | `45223f61306a6784330c3657ddb022c5237a18695c73ede45f77bf502fa5f058` |

The referenced neutral ECR image exists: `biomate/workflow-tools:x86`, digest `sha256:b68d6f5bfcfec7c0fe0b5f6fdd6464863ec420d6fd952e0e1cd809aee49b8af4`. This verifies image identity/existence, not scientific qualification of every tool in it.

Archive extraction emitted repeated macOS provenance-xattr warnings; every source hash and the health/build gate passed. Future archive generation should set `COPYFILE_DISABLE=1`. No retry or code change was used to hide those warnings. The host-side sync lock was supplemented by a live local lock holder so the workstation's supported sync script could not race the scoped deployment.

Current status: PR open, scoped local-to-dev sync complete and healthy, online acceptance tests in progress. Not yet ready for teammate acceptance.
