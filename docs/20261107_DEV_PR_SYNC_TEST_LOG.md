# Dev scientific readiness PR sync and test log

## Scope and deployment review

Requested on November 7, 2026, America/Chicago: create a PR, sync the local changes to dev, and test the deployed platform. At the start, the live frontend identified commit `7c030334b439df2ecc7d384e7c2812c1a59c843f`, the head of PR 328 (`codex/zh-en-ui-parity`). The new fixes are based on that deployed commit, not the older active shared-checkout HEAD. Existing language, project-chat and report fixes must remain intact.

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

Status immediately after the first deployment: PR open, scoped local-to-dev sync complete and healthy, online acceptance tests in progress. Not yet ready for teammate acceptance at that point.

## First post-sync live acceptance and corrections

The first post-sync Playwright batch failed two tests. These failures are retained, not replaced by a local regression pass. The ADMET request produced the intended draft, but the peptide request selected an antibody workflow. The target request supplied a disease name that is an official exact synonym rather than the canonical ontology label; the name-only resolver rejected it. The actual target-handler channels can operate from dev; these were routing/resolution defects, not established credential failures.

The scientific execution test launched real AWS Batch work through the authenticated platform. Ethanol run `9a559a44-1ef0-40e0-bba7-01d842436f3d` (Nextflow `074e47dc-3a0d-4682-affc-754c31ddf8be`) completed. Its downloaded CSV reported molecular weight 46.07, TPSA 20.23, three heavy atoms, one donor, one acceptor, molar refractivity 12.76 and QED 0.4068. Its JSON reported success. This validates the selected deterministic fixture, not predictive ADMET accuracy.

Invalid-SMILES run `d5ff7047-0a85-4cb7-9239-2efd7f5af952` (Nextflow `459a1cfd-f2f2-4438-af8d-9afb122e86b4`) correctly failed with a SMILES parsing error. However, its diagnostics API returned HTTP 500 because it used a Galaxy invocation URL for a direct Nextflow run. The negative acceptance test therefore failed. The deployed branch already had run-ownership protection; the correction preserves that guard and changes the execution-engine dispatch, not public log exposure.

Reviewed follow-ups direct basic unmodified linear peptide calculations to the existing sandbox/BioPython tool, accept source-verified `hasExactSynonym` disease terms without accepting fuzzy matches, and route direct Nextflow diagnostics to its status API. Folding, cyclic/modified peptides and genuine workflow requests remain outside the basic sequence shortcut. The diagnostics endpoint remains explicitly authenticated; internal logs are not automatically dumped into chat.

Release `815132435eda2036845b346d407cdf784120ac67` passed its exact-source TypeScript check and 83 focused frontend tests. The shared-source full frontend suite passed 2,304 tests with 32 skipped; those skips do not establish live coverage. The routing/resolver suite passed 28 tests and the target-handler suite passed 12. An earlier full-suite SIGSEGV and the first live failures remain recorded as unsuccessful attempts.

Pre-deployment SSM check `7b8df196-9175-42ca-b167-977ebcc83a8a` succeeded against real services: Open Targets resolved “non-small cell lung cancer” to `MONDO_0005233` through its official exact synonym, and the existing dev tool image returned peptide molecular weight 2395.7134 and pI 6.784552192687988. No package installation or credential change was required.

The second local release archive contains 1,034 manifest-verified files, is 20,085,959 bytes and has SHA-256 `7fb993051f60a5f6d0c9a9ed54af545d48d9d1690d5173de2f130ba4b103a813`. Its baseline is the first deployed commit `4dde598fd1d78fd77e0833e0da5f0ea4c084f1b9`. SSM deployment command: `840c7236-2b4b-431c-8a18-e954bc124bd9`.

## Follow-up deployment

SSM completed successfully with `result=healthy`; the public build endpoint independently identified `815132435eda2036845b346d407cdf784120ac67`. Frontend image ID: `sha256:deac154809d5efc5bf565004046eeef0cf3fd34e2a1f65d89941fc5ab0866ae5`. Rollback container: `biomate-dev-frontend-rollback-815132435eda`. Runtime backups are in that commit's release directory on dev. The changed disease resolver hash is `1ad63fabc6d93f8c0276cd09c08deadef82033669b9ad9eec6185663b09bb3d0`; the other three runtime hashes match the first deployment table. Databases were not replaced. The local and remote sync locks were released on completion.

The backend was temporarily unavailable during the controlled master reload, then passed the health gate before the frontend swap. Both API and AI returned `ok`, Galaxy connected, and the version API returned 25.1 before live acceptance began. Despite `COPYFILE_DISABLE=1`, this archive still contained macOS provenance extended headers, which GNU tar warned about. This does not alter the verified source hashes; future archive generation should explicitly omit xattrs, rather than assuming that environment setting removes them.

Post-fix live command, run from `frontend/` with the existing fixture and no traces:

```bash
BIOMATE_URL=https://dev-public.biomate.ai \
  node node_modules/@playwright/test/cli.js test \
  e2e/dev-online-readiness.e2e.ts e2e/dev-scientific-properties.e2e.ts \
  --project=chromium --workers=1 --retries=0 --reporter=line --trace=off \
  --output=/private/tmp/biomate-pr335-postfix-live-tests
```

The post-fix ethanol assertions additionally require exact reference QED, TPSA and hydrogen-bond acceptor count. A merely positive QED value no longer passes. At that point the live result was pending; the completed verdict and cleanup review are recorded below.

### Interpretation audit during the repeat run

On `8151324`, all three structured chat cases passed their existing assertions: ADMET selected the intended workflow; peptide `run_code` returned molecular weight 2395.71 and pI 6.78; target identification returned EGFR with score 0.8884, successful Open Targets/STRING channels and no channel errors. The target response explicitly distinguished association scores and model judgment from independent scientific validation. Evidence: `run-1794113229656/preflight-results.json`.

Manual review nevertheless found an error outside the original peptide numerical assertions: the response said “instability index (>64)”. The documented ProtParam convention uses 40, and this empirical protein heuristic is not a validated experimental stability result for the short peptide. Reference: [ExPASy ProtParam documentation](https://web.expasy.org/protparam/protparam-doc.html). The original automated peptide PASS therefore does not mean the whole answer was scientifically acceptable.

Follow-up commit `e06ade54e1bc8cae058fcd52c8895cc946e1b45c` grounds that interpretation in the documented convention and warns against claiming measured stability/half-life. It adds a live regression for the observed invented threshold and retains the full peptide response for review. That regression is deliberately described as narrow, not a general scientific-language validator. All 14 sequence-routing/instruction tests and the exact candidate TypeScript check passed. Do not change the older evidence to hide the finding.

### Verified second live batch

The batch on `8151324` completed with **2 Playwright tests passed in 4.0 minutes**, no retries and no skipped live cases. Every existing structured preflight assertion passed, and cleanup succeeded. The manual interpretation finding above remains a separate failed quality finding despite that automated result.

Scientific evidence: `scientific-1794113365310/`. Ethanol run `f33302a7-9d8a-4ea9-b438-eb0d8a010697` (Nextflow `acc5554b-b2f2-4fda-80fc-3d45a6a9f7e9`) completed and its downloaded CSV/JSON passed all strengthened reference assertions. Invalid-SMILES run `3a3d2640-5569-4060-9c9d-de3358c98f92` (Nextflow `5d7811dd-a6dc-4469-aead-063d73829d98`) correctly failed. Its authenticated diagnostics now returned successfully and the actual failure was SMILES parsing, not infrastructure or workflow compilation. The temporary terminal project was removed with HTTP 200. No owned job remained active before the final sync began.

### Final interpretation-only application release

Candidate `e06ade54e1bc8cae058fcd52c8895cc946e1b45c` is exported from local Git, with baseline `815132435eda2036845b346d407cdf784120ac67`. Only the guarded peptide instruction changes runtime behavior; the four backend/workflow source hashes and diagnostics route are unchanged. The archive contains 1,034 verified source files, is 19,898,087 bytes and has SHA-256 `061a76eb48d1c3512317ddc6babd6812a5a7214a66efd6268397bae117b0aa22`. It was generated with Python tarfile from Git archive content to avoid inheriting macOS xattrs.

SSM sync command: `6b4118df-d485-4d86-ba54-44f50b984090`. This uses the same reviewed baseline/backup/health-gated procedure, after the scientific jobs finished. The final deployment and interpretation-regression verdict follow.

The final sync succeeded with `result=healthy`; public `/build-info.json` independently returned `e06ade54e1bc8cae058fcd52c8895cc946e1b45c`. Image ID: `sha256:3216b9ee9a30d18cb4c8d1421b3df94fab2830e6e9f72637bd6eb7a66dca6f0a`. Retained rollback container: `biomate-dev-frontend-rollback-e06ade54e1bc`. All four runtime fingerprints matched the preceding release. Databases were not replaced, and both sync locks were released. The final tar extraction had no provenance-xattr warnings. Backend import/reload emitted existing package/configuration deprecation warnings (including `pkg_resources`, legacy Galaxy path settings and the `validate` model-field name); these did not fail import or health, but are not being presented as fixed by this PR.

The final preflight additionally records the actual peptide code, correlates its call/result with `tool_use_id`, requires the BioPython molecular-weight and pI method calls and prevents printed JSON from overriding the real tool exit status. It retains the full peptide response for manual review. These are test-only changes after the deployed application commit; they do not require another application sync. The live scientific harness passed on `8151324`; the final guarded peptide-only prompt change does not modify its tested execution, output or diagnostics path.

## Final scoped acceptance verdict

On the final deployed application `e06ade54e1bc8cae058fcd52c8895cc946e1b45c`, the consolidated preflight passed in **2.5 minutes**, with **all 14 ledger checks passing**, no retry and no skipped case. Evidence: `run-1794113868148/preflight-results.json`. The public build ID matched before and after testing. Its authenticated workbench screenshot was reviewed visually.

ADMET selected the intended structured draft without dispatch; this is not a predictive-model accuracy pass. Peptide code called actual BioPython methods, returned the expected molecular weight/pI and passed the observed interpretation regression. The full response now uses the documented 40 convention and states that its results are theoretical, not validated experimental half-life. That does not validate protein-stability heuristics for short peptides. Target evidence returned EGFR score 0.8884 with successful Open Targets and STRING channels and no channel errors. All three test sessions and the temporary project were cleaned up; the project had zero Nextflow runs. The actual descriptor positive/negative execution evidence remains the preceding verified batch, whose runtime path is unchanged by the final prompt-only correction.

The team handoff is ready for the **specified online UI acceptance pass**, with fixtures, tolerances, artifact hashes, exact run IDs, configuration checks and reproduction commands. It explicitly lists broader scenarios not run in this scoped qualification. This is not comprehensive platform approval or a complete small-molecule/cyclic-peptide/training demonstration sign-off. Original failed ledgers and scientific artifacts are retained alongside the successful retests. Authentication traces, environment values and presigned URLs are excluded from the evidence commit.
