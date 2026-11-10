# Docker image name migration ledger

Date: November 7, 2026.

## Authorized scope

Phase 1 removes the old upstream name from BioMate Docker build directories, image repository names and offline archive names, then updates their workflow, CI, installer, runtime and catalogue consumers. Python package imports, unrelated workflow roots, scientific tool IDs, licences and historical research are not renamed in this phase. No old ECR repository or image will be deleted during migration.

## Naming and audit records

The explicit map is `scripts/release/image_name_map.json`. Neutral destinations include `workflow-tools`, `admet`, `pharmacology-tools`, `structure-to-drug` and `drug-discovery-nf`. All 14 corresponding ECR destinations were absent in the November 7 preflight. A further historical `biomni-docking` reference is mapped to `docking-tools`; availability must be checked rather than invented.

`scripts/release/migrate_image_names.py` plans exact mechanical substitutions, records before/after SHA256 hashes, preserves modes and existing unrelated edits, refuses destination collisions and saves rollback source copies. The catalogue migration is transactional and journals exact changed cells before commit; search indexes are rebuilt from primary records.

Detailed artifacts live under `docs/qa/20261107-image-name-migration/`. Historical inventory remains under `docs/qa/20261107-upstream-name-audit/` and is not rewritten.

## Preflight findings

- The working tree has extensive unrelated user/research changes. No reset, cleanup, broad commit or overwrite is authorized.
- Docker is not installed locally. The existing AWS dev host is running, tagged `Env=dev`, and online in SSM. Its name tag contains Production, so target identity must always be checked by instance ID and Env tag, not name alone.
- The catalogue is an ignored runtime SQLite database; its migration must be recorded separately from Git diffs and carried into an eventual released seed database.
- ECR destination names were verified unused. Registry copying must preserve source manifest digests, tags and architecture lists. A renamed repository alone does not prove a runnable image or clean layer contents.

## Acceptance gates

1. No mapped old image component remains in active BioMate workflow container references, build paths, CI consumers, runtime image mappings or catalogue image references.
2. Docker build directory moves and CI relative paths resolve; shell syntax, YAML, Python and TypeScript/regression checks pass in proportion to the changed code.
3. Replacement registry tags resolve to the intended source digests, including architecture-index children. Old tags are preserved; conflicting destinations are never overwritten.
4. Representative containers run the existing smoke scripts on the exact replacement references. A missing dependency or failed smoke is a failure, not a skip/pass.
5. On-prem installer/Compose generation and a representative workflow use neutral references. GHCR/ACR/offline distribution availability is verified separately from AWS ECR.
6. No deployment is called complete until its exact released assets pass verification. Pending registry, credentials, seed-asset or execution gates remain explicit.

## Current status

Local image-consumer migration applied; deployed consumers have not been updated. Registry destinations exist but image copies and container smoke tests are still pending. This phase is not release-complete.

## Detailed operation record

1. Planned and applied an explicit mechanical substitution pass to 1,555 files. This was a count of files touched, not 1,555 renames or scientific-method changes. Only 15 files moved: ten files under four Docker build directories, plus five CI workflow files.
2. Original extension breakdown: 814 Nextflow definitions, 424 Nextflow configurations, 237 Galaxy XML wrappers, 15 Python scripts, 11 YAML files and 54 other files. The shared container reference is repeated in workflows, profiles, wrappers and generators.
3. Scope review restored 32 nonrelease files to their exact pre-task bytes: seven archived workflow/config files, twenty historical JSON test results, three generated/prototype HTML files and two historical Markdown notes. Each restore checked both the current post-migration hash and saved original hash first. Existing user changes were preserved. The original mechanical batch now retains 1,523 file changes. `scope_restorations.json` lists all 32 restorations; the original ledger and patch remain an honest record of the first pass.
4. Added explicit backend Docker build exclusions for those archive/report trees and historical notes. They remain in the repository, unchanged, but must not be packaged as runtime release inputs. Active source and guide references remain migrated.
5. A follow-up review corrected the reusable-build-template name in the ADMET CI comment. The Docker SDK/package import itself was not renamed.
6. The first SQLite transaction attempt failed at BEGIN IMMEDIATE, before updates. Follow-up isolation confirmed BEGIN/ROLLBACK worked. Disk free space was briefly only about 147–185 MiB; this is a material environmental risk, not a proven diagnosis of that initial error. No user files were deleted to recover space. The guarded database-only continuation subsequently committed 895 changed cells in `tools` and `workflows`, rebuilt search indexes and passed integrity checks. Exact original/replacement cell values are saved in `database_changes.json`.
7. Preserved one untracked compiled smoke-test cache by moving it to the neutral build directory; no cache contents were deleted. See `untracked_moves.json`.
8. Created 14 private neutral ECR destination repositories with matching encryption/scanning/tag-mutability configuration and an ownership marker for safe resume. Source repositories/images are untouched. The frozen registry plan contains 160 digest records and 111 tag references. No images have yet been copied or smoke-tested under their new registry references.

The batch count excludes newly added audit/migration/test tools and subsequent small review corrections. It is not a count of every dirty file in the shared workspace.

## Test record

- Naming regression suite: initial pre-migration run had four expected failures; after file moves it exposed the not-yet-migrated catalogue and the untracked cache remnant. One run overlapped the uncommitted catalogue transaction and still observed old catalogue values. The completed-transaction rerun passed all eight checks with no skips. Timestamped subsequent attempts are retained alongside `tests-after.json`.
- TypeScript: passed `tsc --noEmit -p .`.
- Shell: `bash -n install.sh` and `bash -n scripts/sync_to_dev.sh` passed.
- YAML: 34 Compose/CI YAML files parsed.
- Frontend regression: the sandboxed run produced localhost listen EPERM errors. The rerun with socket access completed with 2,275 passed assertions, 32 skipped and one failure. Counts are derived from assertion statuses; this Vitest JSON version's aggregate numPassedTests misleadingly includes skipped assertions.
- The remaining regression failure is the pre-existing `doc-code-drift.test.ts` expectation of 69 workflow chains. Both the current catalogue and a pre-migration November 5 backup contain 70. The image migration does not insert/delete chain rows. No catalogue data or expected value was changed merely to make that test green.
- No live container smoke test, on-prem installation, registry-tag parity verification or workflow execution is counted as passed yet.

### Follow up audit on November 7

The regression suite now has eleven checks, all passing without skips. Three additional checks verify every one of the 895 journaled catalogue cells against its committed replacement, compare all stored tool-search content with primary tool records rather than just row counts, and verify the SHA256 of each of the 32 restored historical files. These are local integrity checks, not container execution results.

The first remote copy command, `7655d2a5-24fe-497e-bc92-74179b06d761`, failed at `ecr get-authorization-token` with a connect timeout to the ECR API endpoint. It failed before creating the credential file or copying an image. This is not evidence of invalid AWS credentials. A subsequent read-only inventory confirmed zero images in all fourteen neutral destination repositories.

Static review also found a latent credential-file ownership defect in `scripts/release/copy_images_remote.py`: its root-only auth directory/file cannot be read by the official registry-client image's default `appuser`. That runner issue remains open and must be corrected before retrying; it was not the cause of the observed ECR API timeout. No retry, IAM change, registry-setting change or application deployment was performed in this follow-up audit.

## Remaining publication gates

ECR blob mounting is disabled. An optional request to enable it is pending; no registry setting or IAM permission was changed. The dev instance already has an ECR push policy, so an ordinary in-region streaming registry copy is an alternative without changing that setting. Docker is available there with approximately 20 GiB free; task-image layers should be streamed by a registry client rather than unpacked into the dev daemon's image store.

GitHub authentication works when network access is allowed, but the current OAuth scopes do not show write:packages. GHCR publishing needs an authorized package-write route, such as the existing repository CI token. ECR availability alone will not complete the GHCR/on-prem distribution gate. No application sync/deployment has been run.
