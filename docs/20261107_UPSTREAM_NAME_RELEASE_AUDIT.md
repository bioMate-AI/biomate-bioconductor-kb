# Biomni references in the on premise release

Date: November 7, 2026. Read-only inventory of `/Users/kky/biomate-review` and AWS ECR in BioMate account `399683337364`.

## Decision summary

The name appears in deployable infrastructure, workflow and tool identifiers, actual Python dependencies, catalogue data, installer output, prompts, and historical research material. It is not confined to comments or a few old image names. A global string replacement would risk breaking execution and misrepresenting third-party origins.

The recommended release objective is **BioMate branding and neutral operational names, with accurate third-party attribution retained where required**. If the requirement is literally no occurrence anywhere in delivered software, the remaining upstream dependency and distribution obligations must be resolved explicitly; renaming an image does not remove the software inside it.

No application files, database entries, images, repositories, IAM settings or deployments were renamed, deleted or updated. Only this report, the read-only scanner and inventory artifacts were created.

## Coverage and counts

| Surface | Result |
| --- | --- |
| AWS ECR scope | All 17 enabled commercial AWS regions in account 399683337364; ECR Public in us-east-1; no API errors |
| ECR resources inspected | 96 repositories; 689 image-digest records, including untagged records |
| ECR matches | 14 repositories; 160 digest records, all in us-west-2; 55 matching digests are untagged |
| Neutral repository names | No image tags containing the term were found in otherwise nonmatching repository names |
| Local file inventory | 170,164 files, including ignored/hidden files and a nested worktree; Git object history excluded |
| Text matches | 234,985 occurrences on 119,939 lines across 10,272 files |
| Main checkout excluding nested worktrees | 188,796 text occurrences across 5,244 files; 5,163 of those files are tracked |
| Matching paths | 43,616 file/directory path entries: 36,174 files and 7,442 directories, counting descendants of named directories |
| Direct basename matches | 513 file basenames and 32 directory basenames; this is distinct from inherited path matches |
| Primary SQLite files | Three scanned; catalogue has 8,208 matching cells across 2,200 rows; other two have no matches |
| SQLite backup copies | Three scanned; each has 8,208 matching cells across 2,200 rows; these are duplicated historical copies, not additional unique functionality |
| Binary/archive supplement | 3,483 candidate files; 2,446,788,273 raw bytes inspected; 168 matching files across 248 records; no errors or size-limit skips |

ECR digest records include OCI/Docker manifests and multi-architecture indexes. They are not 160 distinct runnable builds. Text, path, database and binary counts overlap and must not be summed into a single “total mentions” number. Matching lines can contain several occurrences. Counts describe the scan snapshot, not an immutable repository state.

## Full inventories

The exhaustive location lists for the scanned surfaces are machine-readable rather than truncated into this summary. Text and database records retain matching identifiers and locations, not entire source lines or database values, to avoid copying unrelated secrets.

| Inventory | What each record identifies |
| --- | --- |
| [ECR repositories and image digests](qa/20261107-upstream-name-audit/ecr.json) | Account, region, repository URI, all matching digests/tags, sizes, push dates, media types and match reason; also region coverage/errors |
| [All matching paths](qa/20261107-upstream-name-audit/paths.jsonl) | File/directory path, category, direct-basename versus inherited-path match, and file tracking status |
| [All matching text files](qa/20261107-upstream-name-audit/files.jsonl) | File, occurrence and line counts, matching identifiers and category |
| [Every matching text line](qa/20261107-upstream-name-audit/text_occurrences.jsonl) | File, line, byte offset, match columns, identifiers and tracking status |
| [Every primary database cell](qa/20261107-upstream-name-audit/database_cells.jsonl) | Database, table, row identity, column and matching identifiers; matching schema objects are separate records |
| [Every backup database cell](qa/20261107-upstream-name-audit/database_backup_cells.jsonl) | Backup path, table, row identity, column and matching identifiers |
| [Primary database coverage](qa/20261107-upstream-name-audit/databases.json) and [backup coverage](qa/20261107-upstream-name-audit/database_backups.json) | Per-database and per-table counts and errors |
| [Binary/archive matches](qa/20261107-upstream-name-audit/binary_occurrences.jsonl) | File and literal-byte offsets; ZIP member names/content offsets where applicable |
| [Text/path scan summary](qa/20261107-upstream-name-audit/local_summary.json) and [binary summary](qa/20261107-upstream-name-audit/binary_summary.json) | Counts, explicit exclusions, errors and limitations |

Scanner: [audit_upstream_mentions.py](../scripts/audit_upstream_mentions.py). It uses case-insensitive matching, includes hidden/ignored files, paginates ECR APIs, and queries SQLite with `mode=ro` and `query_only`. It does not authenticate Docker, pull/run image layers, execute stored code or unpickle models.

## Complete matching ECR repository list

All repositories below are in `us-west-2`, under registry `399683337364.dkr.ecr.us-west-2.amazonaws.com`. Full image tags and digests are in the ECR inventory.

| Repository | Matching digest records |
| --- | ---: |
| `biomate/biomni-admet` | 75 |
| `biomate/biomni-tools` | 23 |
| `biomate/biomni-structure-to-drug` | 14 |
| `biomate/biomni-drug-discovery-nf` | 10 |
| `biomate/biomni-microbiology` | 9 |
| `biomate/biomni-pharma` | 9 |
| `biomate/biomni-cloning` | 3 |
| `biomate/biomni-crispr` | 3 |
| `biomate/biomni-systems` | 3 |
| `biomate/biomni-synbio` | 3 |
| `biomate/biomni-structural` | 3 |
| `biomate/biomni-tools-base` | 3 |
| `biomate/biomni-structure-to-drug-gpu` | 1 |
| `biomni-lite` | 1 |

The other scanned regions contain no matching repository/image-tag names. The account has no ECR Public repositories. Other AWS accounts/partitions are outside this verified scope. Non-opted-in regions are listed in the coverage record but were not queried for repositories.

## Release relevant local surfaces

### Installer and deployment artifacts

- `install.sh:332–354` pulls `ghcr.io/biomate-ai/biomni-tools:latest`, tags `biomate/biomni-tools:latest`, and prints the term in operator-facing status/error/offline instructions.
- `.env.onprem.example:236–240` documents `BIOMATE_BIOMNI_TOOLS_IMAGE`, the GHCR image and offline tar filename.
- `docker-compose.onprem.yml` contains image examples and a live mount destination `/app/biomni_workflows/nextflow_nfcore`. A filesystem rename therefore requires coordinated mount and resolver changes.
- `.github/workflows/build-biomni-*.yml`, `build-admet-image.yml` and `build-nextflow-base-image.yml` contain workflow names, Dockerfile paths and image references.
- `.github/workflows/sync-to-acr.yml` contains 51 occurrences, including Alibaba ACR/GHCR mirroring and deployment instructions. Changing AWS ECR alone will not change those release channels.
- `backend/.dockerignore` and `backend/Dockerfile` govern which workflow trees and other backend sources are copied. Audit the actual release image contents rather than assuming a renamed source directory is absent from a built image.

### Images and actual dependency imports

- `backend/docker/biomni-tools/Dockerfile` and `Dockerfile.onprem` contain image labels, smoke output and a real `pip install "biomni>=0.0.8"` dependency. These are not merely stale image names.
- Other Dockerfiles reference the matching repositories in `FROM`, examples, lockfile paths, labels and smoke messages. Relevant trees include `biomni-admet`, `biomni-pharma`, `biomni-structure-to-drug`, `drug-discovery-nf`, `foldseek-awscli` and `mmseqs2-awscli`.
- `backend/lib/galaxy/ai/generate_biomni_nextflow.py` emits `from biomni.tool.<domain> import <function>`, named processes, image defaults and configuration text. Updating existing files without updating generators would recreate the old names.
- `Biomni/` contains upstream source; `backend/biomni_workflows/` contains the large workflow tree. The two are different migration concerns: dependency provenance versus BioMate operational organization.

Some comments describe the pip dependency as a BioMate SDK. That wording should be reconciled with the actual package provenance and licensed source rather than simply replaced with another ownership claim.

### Runtime lookups and persisted identifiers

- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` resolves workflow paths under `biomni_workflows`, accepts `biomni_nf/` aliases and handles image overrides/normalization.
- `backend/lib/galaxy/ai/ai_assistant.py` and `nextflow_composer.py` contain workflow roots, alias handling and generated-container defaults.
- `frontend/server/galaxy-api-proxy.ts` translates `biomni/...` tool IDs to underscore-form Galaxy identifiers. This requires a migration/compatibility decision, not a cosmetic edit.
- `frontend/shared/galaxy-types.ts` exports `BioMNIDataset`; server code imports it and uses it in dataset response types.
- `frontend/server/galaxy-assistant.ts:8844` emits the explanation `Retrieved from BioMNI catalog`. This is a potential user-facing text leak, unlike an internal comment.
- `frontend/client/src/components/workflow-disambiguation-card.tsx:33` uses source key `biomni_nextflow` but already maps its visible label to **BioMate**. Preserve the distinction between an internal identifier and displayed branding when deciding priority.
- `frontend/client/src/components/chat-interface.tsx` has source comments; `frontend/client/src/lib/corrections.test.ts` has fixture source keys. The full inventory distinguishes these from rendered strings.

### Catalogue database

`backend/database/galaxy_ai_tools.db` contains the following matching rows/cells:

| Table | Matching rows | Matching cells |
| --- | ---: | ---: |
| `tools` | 619 | 4,399 |
| `workflows` | 508 | 1,572 |
| `tool_knowledge` | 275 | 310 |
| `dataset_tool_mapping` | 202 | 202 |
| `tools_fts_content` | 596 | 1,725 |
| Total, including search-index mirror rows | 2,200 | 8,208 |

There are 1,604 matching rows outside the FTS mirror. Important columns include `tools.tool_id`, `name`, `wrapper_path`, `repo_name`, `repo_owner`, `rawText`, `help_text`, `container_info` and `execution_info`; `workflows.source`, `tags`, `workflow_json`, `docker_image`, `filename` and descriptions; and knowledge/dataset mappings. The cell inventory lists every matched row/column, not just these examples.

The compliance and regulatory-skills databases have no matches in the scanned tables. Three November 5 catalogue backups repeat the same 8,208-cell/2,200-row counts. A migration must update dependent IDs and embedded JSON consistently and rebuild search indexes, while keeping backups out of distributable packages.

### Prompts and historical material

`frontend/server/model-test-harness.ts`, backend workflow generators and knowledge/RAG modules contain the name in model context or source descriptions. These can regenerate old terminology even after UI labels change.

Documentation/reference material accounts for 122,040 text occurrences; research/evaluation accounts for 35,118; nested worktrees account for another 46,189. Training examples, benchmark labels, papers and historical records need a release-packaging policy, not indiscriminate rewriting of scientific comparisons. Keep internal history out of release artifacts where unnecessary; retain accurate benchmark attribution in research records.

## Handling options for discussion

| Category | Recommended treatment | Verification needed |
| --- | --- | --- |
| Product UI, install messages and operational labels | Rename to BioMate or neutral scientific capability names | Rendered UI, install/offline walkthrough, generated reports and logs |
| Image repositories/tags | Publish neutral-named release images and change consumers together; do not delete old repositories during migration | Digest/architecture parity, workflow smoke tests, GHCR/ACR/offline bundle checks |
| Workflow directories, modules and class names | Explicit old→new mapping; coordinate imports, mounts, resolvers and generators | Fresh install, existing-project execution and generated workflow tests |
| Tool IDs, catalogue source keys and dataset mappings | Transactional/versioned migration with dependency checks; decide whether compatibility aliases remain internal | Referential integrity, search-index rebuild and old-project replay |
| Actual upstream Python package/code | Choose supported vendoring, replacement or retention based on real usage and licence review; a renamed wrapper is not removal | Dependency/SBOM review, functionality parity and source/notice verification |
| Archives, backups, caches and nested worktrees | Exclude unnecessary copies from the release using an explicit artifact allowlist | Inspect final images and offline bundle, not just Git status |
| Scientific comparisons and legally relevant notices | Preserve accurate provenance; separate from product marketing | Research integrity and redistribution review |

The checked-in `Biomni/LICENSE` is Apache-2.0. Its redistribution provisions address licence copies and relevant notices, including NOTICE handling when applicable. Treat those separately from optional branding and have the actual shipped components reviewed before removing attribution. See the [official Apache-2.0 text, section 4](https://www.apache.org/licenses/LICENSE-2.0). This inventory does not establish the licence/version of every installed package or container layer.

No rename or removal has been approved or carried out. The first decision is whether the objective is **no optional customer-facing branding** or **removal/replacement of the upstream dependency itself**. Those require different scopes and acceptance criteria.

## Limits before claiming a clean release

- This is a current-checkout inventory, including hidden and ignored files; not a scan of all Git history, sibling repositories, remote databases or every organization account.
- Symbolic-link targets are not followed. SQLite views/virtual tables and binary FTS shadow tables are not evaluated; primary tables and text FTS mirrors are covered.
- Binary files were searched for literal bytes; recognized ZIP-based archives also had member names and decompressed member bytes checked. PDFs were not OCRed or fully decoded; gzip/tar and nested archives were not recursively unpacked. Encrypted or compressed text can therefore remain undiscovered.
- ECR repository/image tags were inventoried; image layers, config labels, installed packages, image history, generated SBOMs and embedded files were not pulled/inspected. A neutrally named image may still contain the package or old text.
- GHCR and Alibaba ACR references were found locally, but those remote registries and S3 release bundles were not inventoried live.
- The audit scanner/report/artifact directory is intentionally excluded from its own counts. These audit materials themselves mention the term and should not be placed in a name-clean customer package.

After agreeing the handling policy, define an allowlist for required notices, scan the built release artifacts and rendered outputs, and require zero unexpected matches outside that allowlist. A source-only search cannot certify the on-prem distribution.
