# On premises release readiness implementation log

Date: November 7, 2026. Status: implementation in progress, not a release-completion certificate.

The internal documentation/configuration audit is published separately in [PR 329](https://github.com/bioMate-AI/biomate/pull/329), commit `dbd58b9aed3a8ba4395622607055f5598882f5f9`. That PR contains fifteen audit files only. It does not replace the customer manuals, deploy fixes or certify absence of legacy names. The shared working branch and pre-existing staging area were preserved during its creation.

## Diagnostic bundle privacy

Baseline: the diagnostic script in approved next-phase merge `79c0421d9` exports full container inspect JSON, log bodies, recent-run metadata and partially redacted configuration, and suggests a public upload service. The implementation retains the approved script as its starting point and changes the privacy boundary explicitly.

| File | Implemented change | Verification |
|---|---|---|
| `scripts/diag-onprem.sh` | Default collection is metadata-only. Log bodies and run records require both `--include-sensitive` and `--confirm-authorized`. API bodies are not captured by default. Raw inspect JSON is projected through the privacy helper. Configuration exports names/presence only, never comments or values. | Six privacy unit/CLI contract tests pass. Shell syntax passes. |
| `scripts/onprem_diag_privacy.py` | Allowlisted inspect projection excludes environments, commands, labels, mounts, arbitrary state/error strings and health-output bodies. Environment summary reports valid key names and presence only. Malformed input fails without echoing it. | Synthetic secret canaries cover nested inspect fields, environment values/comments and malformed input. |
| `scripts/test_onprem_diag_privacy.py` | Tests helper behavior and executes the actual shell collector against synthetic Docker/HTTP commands. Asserts no canary in stdout or any generated file, metadata-only contents, restrictive directory mode, explicit sensitive-mode authorization and `--no-pack` behavior. | 6/6 pass; these are fixture-based CLI tests, not live Docker or hospital qualification. |

The collector now creates unique owner-only directories and archives under a restrictive umask, honors `--no-pack`, rejects unknown flags and no longer recommends public file-sharing uploads. A complete deployment package must include the Python helper; a standalone downloaded shell script fails closed if the helper is missing. This packaging/documentation change still needs delivery verification. Metadata can itself reveal infrastructure details, so customers must review even default bundles before approved transfer. Sensitive mode is explicitly not an automatically redacted export.

The first CLI test attempt failed because its synthetic curl command ignored `-o /dev/null`, unlike real curl, and emitted the canary body. The fixture was corrected to model output suppression, and its inspect response was strengthened to contain actual canaries. No product privacy assertion was weakened to obtain a pass.

## Configuration propagation and production HTML

| File | Implemented change | Verification |
|---|---|---|
| `docker-compose.onprem.yml` | Passes the ten documented Slurm/Kubernetes settings into the backend with explicit defaults. Passes `DISABLE_GOOGLE_FONTS` into the frontend, enabled by default for on-prem. | Two real YAML/template contract checks pass. Scheduler execution is not established by this wiring check. |
| `.env.onprem.example` | Documents the runtime Google-font setting and recreation requirement separately from browser build-time flags. | Template/Compose consistency check passes. |
| `frontend/server/vite.ts` | Integrates the deployment branch's Google-dependency filtering behavior, including root and explicit/encoded index paths before static middleware. Deep links use the same filtering path. Read errors fail instead of returning the unfiltered index. Production no longer mounts the development reference-prototype directory. | Eight real Express HTTP tests pass; TypeScript check passes. |
| `frontend/server/onprem-static.test.ts` | Exercises root, index, deep-link and encoded-index URLs; preserves local scripts and ordinary behavior when disabled; verifies unknown API responses and missing-index failures. | 8/8 pass with localhost socket access. |
| `scripts/test_onprem_configuration_contract.py` | Checks every cluster setting actually documented in the template against backend Compose bindings and verifies the frontend runtime flag mapping. | 2/2 pass. |

The first sandboxed HTTP run failed on `listen EPERM`; complete errors were inspected. The test fixture was improved to reject listen errors immediately and avoid closing a never-started server. The rerun with localhost permission passed all eight tests without skipping or mocking the HTTP server.

Cluster clients, service-account access, shared storage, actual GPU scheduling, container architecture and representative workflows still require live qualification. Host environment settings do not automatically change fixed volume mounts. The local Compose file also contains earlier pending image-name substitutions and is behind some approved storage-mode changes; it must not be copied wholesale over next-phase or deployed from the dirty worktree.

## Image publication runner

`scripts/release/copy_images_remote.py` now uses the previously observed immutable official registry-client digest rather than a mutable latest tag. The trusted read-only, capability-free client runs with the UID needed to read its own root-owned 0600 credential file. Each execution gets a separate private auth directory, and credential creation uses exclusive creation with restrictive permissions from the first write. API requests have bounded connection/read/process timeouts and attempts.

The earlier observed failure was an ECR API connection timeout before any image copy, not an invalid credential response. Bounded SSM probe `a964cd27-609a-4e39-bb88-09b5045b6111` confirmed that the host resolves ECR to private address `172.31.36.99` but receives no HTTPS response. Read-only EC2 inspection identified interface endpoint `vpce-0eaf345d132bb2050` on security group `sg-0de9af2d4437a8c90`. Its HTTPS rules allow two specific groups, neither attached to the verified dev host. The host's outbound groups allow the connection, but the endpoint's inbound rules do not. This explains the observed network timeout without changing or blaming credentials. An existing non-production host already admitted by the endpoint is being checked as an alternative; no IAM or network setting was changed.

## Full regression result

The full frontend rerun with socket access produced 2,283 passed assertions, 32 skipped and one failed assertion. The failure remains the pre-existing catalogue-drift check expecting 69 chains while the database contains 70; the pre-migration backup also contained 70. No data or test expectation was altered merely to make that assertion pass. The eight new HTTP checks pass. Evidence is saved in `docs/qa/20261107-onprem-readiness/frontend-vitest.json`; counts are derived from individual assertion statuses rather than the misleading aggregate field that includes skipped assertions.

## Delivery artifact name gate

Added `scripts/check_release_payload.py` and `scripts/test_release_payload.py`. The checker takes explicit forbidden terms, scans names and raw contents including UTF-16 and read-chunk boundaries, recursively reads ZIP/Word/wheel, tar and gzip layers without extracting or executing them, and fails closed on corrupt/unsupported archives, empty input sets and scan budgets. It records paths/match categories rather than dumping file contents. Seven unit tests pass. It is a detector, not an automatic text scrubber or proof of scientific correctness.

The first baseline scan of the five current Compose/template/extracted-manual inputs failed because Compose still contains legacy runtime paths. This expected failure is preserved in `docs/qa/20261107-onprem-readiness/delivery-name-gate-baseline.json`; it was not relabelled as a clean release. That scan did not cover built images, the complete repository, original Word binaries or the final package, all of which still require their own artifact checks.

## Remaining acceptance gates

1. Complete legacy-name removal across the actual customer delivery files, document formats, executable workflows, application/UI responses and container payloads. Preserve required third-party notices; do not silently erase provenance or historic audit evidence.
2. Reconcile the candidate changes with approved next-phase/storage changes in an isolated implementation commit. Do not publish unrelated shared-worktree changes.
3. Finish and verify image copying, neutral-tag parity, GHCR/offline packaging, seed catalogue and workflow-archive delivery. The named packager referenced by the customer manual is still absent from the reviewed release branches.
4. Correct the customer manuals, with per-section change records and rendered Word verification; remove unsafe recovery instructions and qualify only tested configurations.
5. Complete environment-catalogue ownership/secrecy classification and selected-profile validation. The full generated audit inventory is not a manifest to upload blindly.
6. Run full regression and actual clean on-prem installation/workflow acceptance on the exact release. Local tests are not a substitute for that gate.

No complete clean-release claim, end-to-end on-prem pass or application deployment is made by this log. The later native container result below supersedes the earlier absence of a container test, not the installation gate.

## Continuation: registry publication and native validation

Command `4466e69e-3134-4146-b443-7e498b0c1633` on the existing x86 test host completed. All **166 destination references**, representing **160 image records across 14 repositories**, match the frozen plan's expected manifest digests. The ledger is `docs/qa/20261107-image-name-migration/registry-copy-verified.json`. This checks exact reference-set equality, not only process exit. Full copy logs remain in the dedicated host directory. Initial exports exceeded SSM's output limit and were not accepted; bounded paginated retrieval was then verified successfully.

This is digest-preserving publication, **not image-layer debranding**. Source images remain intact. SDK/module paths inside some images still require migration and fresh builds. No IAM or network setting changed.

Native ARM64 ADMET inference passed with network disabled, one CPU quota and one-core affinity. The immutable neutral image predicted 98 endpoints for aspirin. All four required outputs were present and finite; probability outputs were within [0,1] and all four workflow mappings passed. Full evidence is `docs/qa/20261107-onprem-readiness/native-admet-results.json`. This is functional single-molecule inference, not an accuracy benchmark or application E2E.

The first x86 run stopped before image pull/inference because the host lacked memory headroom; a read-only check found approximately 443 MiB available. No other services were stopped. A separate bounded native x86 job uses the existing CPU queue: `3561a400-577c-4dcb-b932-6be4848ad37b`, one vCPU, 4096 MiB, one attempt and a 300-second execution timeout. Its outcome must be recorded separately; Batch is not network-isolated or an on-prem installation test. The native-host runner now records the failing stage and resource headroom, and cleans up only its own test container on timeout.

That x86 job subsequently succeeded (exit 0, approximately 5.43 seconds running time). Its own logs confirm one-core affinity, 98 endpoints and all four output mappings. `docs/qa/20261107-onprem-readiness/native-x86-admet-batch.json` retains the exact image digest, resource limits, job status and model output. This closes the native x86 container-inference check, not offline/on-prem E2E.

## Catalogue drift reconciliation

The failing 69-chain equality guard was investigated against the actual addition, not simply changed to whatever count was present. The curated Vina benchmark chain (id 77) was introduced November 1 by `backend/scripts/add_vina_bench_chain.py`, commit `4f7f69544`, and is documented with the 70-chain dev inventory in `docs/20261101_OVERNIGHT_STATUS_CHAINS_AND_SYNC.md`. The pre-migration November 5 backup also contains 70. No chain data was inserted/deleted by this fix.

The guard now retains exact equality at 70 and adds an exact four-step contract for that documented chain: IDs, canonical directory slugs, order and executable flags. An initial test incorrectly compared canonical slugs to human-readable display titles; the full failure was read and the check corrected to the actual filename-directory identity (not a fuzzy name match). Historical reports were preserved. This inventory contract is not proof that the chain executes end to end.

The focused catalogue suite passes 19/19. The complete frontend rerun then passed **2,285 assertions, zero failures, with 32 skipped**. These counts come from individual assertion statuses; skipped tests are not passes. The new result is `docs/qa/20261107-onprem-readiness/frontend-vitest-after-reconciliation.json`, while the earlier failure artifact remains unchanged. This green local regression does not satisfy authenticated installation/workflow tests that were not executed.

## Continuation: configuration privacy and stronger tests

`scripts/setup_github_env.sh` previously classified every unknown name as a GitHub Variable, including GOOGLE_API_KEY and CRYOSPARC_LICENSE. It now uses an explicit public-setting allowlist and defaults unknown names to Secrets, with credential-name/URL protection. Values enter gh through stdin rather than process arguments. The header no longer recommends printing live .env through SSM. No live GitHub values were read or changed.

The synthetic CLI test checks classification, actual stdin delivery, no secret canary in output/arguments, empty-value preservation, repository targeting and dry-run non-mutation. It also exposed an existing defect: the final false dry-run condition made successful normal runs return 1. The conditional was corrected; the test passes without relaxing its assertions.

The payload gate now rejects malformed gzip/tgz and unsupported archive suffixes even without magic bytes, and reports unreadable files as structured failures. New depth/unreadable-input checks bring the suite to **10/10**. This does not qualify the full platform.

## Continuation: Word revisions and visual review

The approved source remains `79c0421d9`. The revision builder produces three review-labelled Word candidates with **103 journal entries**: delivery checklist 29, operations manual 46, remote support 28. Their journal records source/candidate SHA256, exact before/after text, coordinates, reasons, moves and layout repairs. Originals were not overwritten during review.

Corrections include secret-printing/raw-log transfer, broad lock/data-volume deletion, backup-root deletion, global Docker configuration replacement, nonexistent packaging commands, host-only file URLs, restart/recreation confusion, unsupported GPU switches, ARM64/QEMU guarantees, CORS/path bypass advice and one-time/auto-expiring remote-session claims. Figures/headings were checked for contradictions as well as command blocks. AI use does not authorize customer-data export.

The bundled renderer initially lost Chinese glyphs because its fontconfig could not resolve/cache installed fonts. Task-local fontconfig/cache and existing Heiti SC references resolved this without font installation or customer-system changes. Missing section/table dimensions were made explicit; table headers repeat, rows do not split and changed long shell commands use continuation lines.

All **43 pages** were visually inspected at original resolution: delivery 14, operations 21, support 8. Final delivery/operations PNGs are pixel-identical to the already-reviewed prior iteration; all eight changed support pages were inspected again. Three regression tests check hashes/comments, unsafe-command removal and table bounds/header structure. The retired-term scan of the Word candidates plus journal passes (52 entries). These remain review revisions pending the matching release's installation, hardware, storage and workflow qualification, not signed customer acceptance.

## Continuation: isolated image-consumer PR and independent object audit

Draft PR #331 is stacked on #330. Its mechanical scope is image repository names, Docker build-folder names, CI filenames and their consumers, not SDK/tool IDs or the workflow root. The source is the approved next-phase tree plus the exact readiness commit, not the dirty working directory. The ledger covers **1,524 file transformations**, with source/destination, modes, before/after Git object IDs and SHA256. Support tooling and the ledger account for additional changed files in the PR. Historical exclusions and upstream source were not silently rewritten. The shared index and active branch were preserved.

`scripts/test_image_consumer_commit.py` reads the actual committed Git tree and blobs. Nine checks pass: every journaled byte/mode, deliberate hash/mode/duplicate-destination corruption, complete change coverage, selected-consumer old-name absence, Python syntax/mechanical-content equality, removal of old build paths, and honest incomplete-release metadata. The first independent run failed because two strengthened smoke files had replaced their initial mechanical versions after their ledger hashes were recorded. Their ledger entries were corrected to the actual committed blobs; the regression checks were not weakened. This is an image-consumer certificate only: upstream SDK imports, payload layers and GHCR qualification remain open.

## Continuation: fail-closed workflow image builds

Two Dockerfiles could swallow installation failures and still print a successful build message. The SaaS recipe now propagates the required runtime-package failure. The on-prem recipe now also propagates descriptastorus, DeepPurpose and runtime failures instead of advertising a heuristic fallback as a working installation. Git is explicitly installed for its git-based dependency; the ARM64 branch includes Vina build tools. OpenCV/PyPDF2 and explicit CPU Torch/DeepPurpose imports align the declared runtime with the SaaS image. The inaccurate comment describing an upstream package as BioMate's proprietary SDK was corrected; namespace replacement remains a release blocker rather than a cosmetic relabelling.

The workflow-tools smoke now calls the actual physicochemical entry point for ethanol, requires the expected CSV/header/SMILES, checks molecular weight, heavy atoms and donors, and requires rejection of invalid SMILES. It also checks finite ViennaRNA output and the required runtime imports. This does not validate ADMET prediction accuracy or redefine approximate properties as scientific measurements.

Four local build-gate tests pass. Crucially, they execute every real shell-form pip-install command with a failing pip function and require propagation of exit 73. A mutation containing the previous `|| echo` clause demonstrably returns zero and differs from the repaired command. Additional checks cover Git/ARM dependencies and the runtime/publication gates. Full rebuilt-image qualification is still pending.

The GHCR workflow's always-running summary previously claimed publication even after a failed/skipped push. It now reports the publication step's actual outcome, prints the pushed-image claim only on success, and explicitly states that its runtime smoke covers amd64 only. No workflow dispatch or live image replacement has been performed by this change.

Bounded existing-queue job `0d93a446-dc19-4322-b475-d265effc01bf` runs the stronger smoke against the immutable current x86 workflow-tools image, with one vCPU, one-core affinity, 6144 MiB, one attempt and a 300-second execution limit. Its result is not assumed from submission or container startup. It tests the existing artifact, not a rebuild of these Dockerfile changes, and is not an on-prem E2E test.

The job subsequently **failed**, exit 1: the immutable x86 image lacks `cv2`. Complete returned traceback and identity are retained in `docs/qa/20261107-onprem-readiness/native-x86-workflow-tools-existing.json`. Assertions after that import did not run and are not passes. Although the current SaaS Dockerfile already lists OpenCV, the tested historical artifact does not provide it. A source edit or neutral retag cannot repair this artifact; a rebuilt or separately qualified immutable image is required. The gate was not weakened to accept missing OpenCV.

The payload suite now has 11 passing tests: PDFs, including disguised PDF magic, fail closed because raw-byte absence does not cover compressed streams, font encoding or image-only pages. They require a separate rendered-content audit. GitHub environment privacy now has two passing tests, including uppercase/encoded/vendor-specific query parameters and fragments; ambiguous URLs remain Secrets instead of relying on a small credential-key denylist. No actual GitHub configuration was changed.

The new on-prem release-contract workflow runs 25 local contract tests (payload 11, diagnostics privacy 6, configuration 2, GitHub privacy 2, build failure 4) on relevant pull requests. These are not actual image builds, architecture validation or clean installation. Their local run passed without skips.

A separate build-only PR workflow now builds the public-base on-prem image and requires a native amd64, single-core, network-disabled functional smoke with a 300-second test timeout. It records the exact local image ID and dependency inventory only after success. It has no registry login, no push and no deployment step. Its result must be checked; adding the workflow does not count as a successful rebuild. ARM64 remains a separate native gate. The smoke's reviewed SHA256 is `cf6f18667e85e60142853633ae42f2d401d21fff7a3d194967fd1953044fd2a1`.

A second bounded job, `d4c5d3f8-b660-4bc2-b15b-0e7ed64f47b7`, checks the separately tagged workflow-tools artifact at immutable digest `sha256:3440967cadfcbc50861da333c3aa9527ea2236dff2d5ba43c87ccb610a3d8039` with the same smoke and resource bounds. The tag's existence and its shared pharmacology digest are not evidence that it implements the full workflow-tools contract; its actual result must be retained separately.

That second job also failed with the complete four-line traceback ending `ModuleNotFoundError: No module named 'cv2'` at smoke line 21, exit 1. Its log stream is `biomate-release-workflow-tools-latest-20261107/default/81de9f0e63d24b7eaecc30fd7deb27f5`. Neither tested existing artifact satisfies the stronger contract; later checks did not execute.

The first contract-CI run exposed a real Python-version incompatibility rather than an installation problem: nested `gzip.GzipFile` inherited an integer `.mode` from its outer stream on Python 3.9–3.12, raising `AttributeError` before the depth/content gate. Local default Python 3.14 did not reproduce it. Explicit `mode="rb"` fixes the reader. The new nested-gzip content assertion checks the actual deepest finding and absence of parse errors, not just a generic failure. All **12 payload checks pass on Python 3.9, 3.12 and 3.14**, bringing the combined local contract total to **26**. The CI rerun must still be observed; the first CI failure is not relabelled as a pass.

Contract rerun `42433468800` subsequently passed. The first real image build (`42433203739`) exposed another previously swallowed failure: the required runtime package version needs Python >=3.11, but the on-prem Dockerfile used Python 3.10. The full build reached DeepPurpose import successfully, then correctly stopped on the incompatible runtime install; smoke and image-inventory steps were skipped and are not passes. The on-prem base is now `python:3.11-slim-bookworm`, matching the runtime's minimum Python version while keeping a public Debian-bookworm base. The regression test guards that exact base; the GHCR workflow's descriptive text is updated too. The corrected build still requires a new actual result.

The Python 3.11 build (`42433606734`) then exposed a missing direct dependency: descriptastorus imports `six`, which was not installed in that environment. DeepPurpose re-raised a generic descriptastorus-install message, but the full traceback identified the actual missing module; reinstalling the same package or weakening the import test would not fix it. Both recipes now explicitly install `six` alongside descriptastorus/pandas-flavor, and the build-gate test guards its presence. The native image build must be rerun; subsequent steps in the failed run remain unexecuted.

## Continuation: remote-support ownership and credential handling

The approved remote-access script was audited against its actual shell behavior. This continuation changes the following, with no live tunnel, system installation, daemon change or host disconnection performed:

- Private owner-only state directory under the operator's state home, restrictive umask and private credentials/config/logs replace predictable public `/tmp` state, executables and PID files. A symlink state directory is rejected.
- `stop` acts only on a recorded session. Tailscale requires matching node identity; frp requires a numeric PID and the exact expected process command; Cloudflare requires the owner label. Missing/mismatched ownership fails without stopping an unrelated process or container. A new session cannot overwrite another recorded session.
- Failed Tailscale authentication cannot print or record success. A zero exit without a Running node stays explicitly pending. Already-running host Tailscale sessions are not taken over, and client installation/shared-daemon configuration are administrator prerequisites, not automatic side effects.
- Plaintext `--key`/`--token` arguments are rejected with migration guidance. New `--key-file`/`--token-file` inputs must be regular, non-symlink, current-owner, owner-only files with bounded nonempty content. Tailscale receives a private file reference, frp writes only its private config, and Cloudflare receives a read-only token-file mount rather than token argv/environment values. Temporary copies are removed after use where the client does not require a persistent mount.
- Unverified automatic frpc downloads and proxy fallback are removed. Administrators preinstall and qualify the executable. Server/port/token configuration is validated; a running process without confirmed login is not reported as an established SSH tunnel.
- Cloudflare requires an explicitly supplied immutable official-image digest, preloaded locally (`--pull never`), a private token-file mount and restricted container privileges. It refuses to delete a pre-existing named container. Its output distinguishes process startup from actual service/Access/SSH validation. The unqualified quick-SSH branch fails explicitly instead of generating a misleading success URL.

The file interfaces were checked against the [Tailscale CLI source](https://github.com/tailscale/tailscale/blob/main/cmd/tailscale/cli/up.go) and [Cloudflare run-parameter documentation](https://developers.cloudflare.com/tunnel/reference/run-parameters/). Cloudflare token-file requires an appropriate client version; a digest alone does not establish compatibility or policy acceptance. Required third-party software and customer access policies still need live qualification.

Eighteen actual shell-entry tests pass on Python 3.9 and 3.14 using synthetic clients, including failure/pending states, existing host sessions, mismatched node/PID records, symlink/insecure credential sources, raw credential option refusal, exact immutable-image requirements and token absence from child arguments. An atomic private-directory operation lock prevents concurrent session mutation; stale locks are not silently deleted. Tests cover both refusal of an existing lock and successful owned-node stop/lock cleanup. They never connect to a support service. Shell syntax passes. These fixtures are not proof of a live FRP/Tailscale/Access deployment.

The three Word review candidates now have **132 journal entries** (delivery 29, operations 46, support 57). Commands, headings, diagrams and troubleshooting text match the file-based interfaces, preinstallation, ownership-scoped stop and independent access qualification. The support manual is seven pages; all seven were visually inspected at original resolution, then its final changed page 3 was inspected again with the other six verified byte-identical. Delivery/operations final renders are pixel-identical to the previously inspected 14/21 pages. Total final pages: **42**. Five document regression checks pass, including content-sensitive, date-only-stable regeneration. Candidate/journal retired-term scan passes: 52 entries, zero findings/errors. This scan does not cover the entire platform or container payload.

Contract CI is extended to 44 runtime/configuration/privacy/build tests plus five Word checks. The exact new commit still needs its own CI outcome. Code/manual changes do not qualify actual customer remote access, clean installation or a zero-mention release. Legacy SDK/workflow paths, licensing/provenance review, rebuilt task-image parity, complete package delivery and end-to-end acceptance remain open gates.

The exact remote-support commit's CI run `42434210172` subsequently passed. A clean export of that Git tree passed 49 contract/document checks locally: 47 with the document runtime, plus the two YAML configuration checks with the system runtime. The first combined run encountered the document runtime's absent test-only PyYAML module; this was not a product failure or a pass. CI explicitly installs both test dependencies and passed in one environment. The active shared branch/index remained unchanged.

## Continuation: rebuilt image qualification passed

Build-only run `42433990224` on commit `229656f852ad3201aad8f42cbc7548ff88889266` passed the actual public-base Docker build and native amd64, network-disabled, one-core functional smoke. The gate required all imports, finite ViennaRNA output, actual ethanol physicochemical CSV values and invalid-SMILES rejection. The job did not log in to a registry, publish an image or deploy an application. Earlier failed builds remain failed evidence. This result is not ARM64 qualification, ADMET scientific-accuracy validation, namespace-clean payload qualification or an install E2E.

## Continuation: installer false-success gates

The installer candidate is formed from the exact approved/stacked release Git object, not the older shared local installer; the colleague's Hygon support block is preserved. Seven regression tests execute the actual candidate shell functions and required-task-image block against synthetic Docker/curl clients. They never run the installer's top level, pull images, change permissions, modify daemons or create administrators.

The repairs require a running **and** healthy container; an existing stopped container, missing health contract, unhealthy/starting timeout or missing container no longer passes. HTTP endpoint failure propagates failure. License acceptance requires the actual JSON boolean `valid: true`, not merely HTTP 200, a truthy string, a number or malformed content. A missing required workflow-tools image aborts, and backend/frontend/task image architecture metadata must match the native host. Architecture metadata still does not establish tool correctness.

The installer no longer automatically runs a privileged binfmt installer or promises unqualified ARM64 availability. Logs use a unique owner-only directory under restrictive umask; failure paths do not dump raw container logs. The final message reports only basic-service readiness and lists the actual user/data/model/workflow acceptance still required, instead of unconditional deployment success.

The tests were run against the old local installer as a deliberate regression check: they detected false-success endpoint behavior, stopped/no-health container acceptance, nonfatal missing task image, missing license/architecture gates and privileged host modification. The revised candidate passes all seven tests without weakening those contracts. One early fixture omitted the real warning function and did not model old/new Docker format expressions faithfully; it was corrected before using this mutation evidence. No complete installation has been executed. Existing world-writable configuration/work-directory permissions, storage-mode initialization, asset completeness, credential lifecycle and remaining startup paths still need hardening/qualification.

The contract workflow adds these seven checks, bringing the next candidate to 56 contract/document checks. Its exact committed CI result is required separately. No merge or live installation is authorized by a green unit/contract suite.

CI run `42434586850` subsequently passed all contract steps on exact installer commit `f6fe452bde740ee811753372f47f179f52b4f26e` (56 tests including Word checks). The older shared local installer was also reconciled to this approved-based candidate only after proving its sole pre-existing difference was the missing Hygon block; that approved block is preserved. The active branch/index were not changed. Publishing these fixes is not completion of the full release. The outstanding attribution-scope question was presented explicitly: preserve required upstream attribution in a separate legal bundle while removing runtime branding, or replace the upstream implementation. Existing legal/provenance material remains intact pending that direction; no zero-occurrence certificate is issued.PR #330's backend CI, frontend CI, security scan, PM wire and test summary have passed; the skipped quick smoke is not a pass. Local frontend regression remains 2,285 passed, 32 skipped. Further open gates include remote-access runtime hardening, full environment ownership/profile validation, a complete qualified package, namespace/layer cleanup and clean-install workflow acceptance. No merge, application deployment, IAM/network change, source-image deletion or unrelated-service shutdown was performed.
