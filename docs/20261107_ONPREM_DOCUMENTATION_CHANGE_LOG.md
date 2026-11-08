# On premises documentation audit change log

Date: November 7, 2026. Scope: review approved customer deployment documentation, recent local on-prem preparations, and environment-management coverage. No customer deployment, GitHub configuration update, remote secret write, commit, push or merge was performed.

## Approved customer manuals

The following originals were read from merge commit `79c0421d90ff86f5973513a0360677bd72df390c` without changing the shared branch:

- `docs/BioMate本地部署交付清单.docx`
- `docs/BioMate本地部署运维手册.docx`
- `docs/BioMate本地部署运维远程支持手册.docx`

All three remain unchanged. `docs/qa/20261107-onprem-configuration/approved-document-provenance.json` records the exact source revision, byte size and SHA256 for each. Content was extracted with Word paragraph, table-cell and line-break text preserved. No layout changes were made or visually qualified.

## Added review and inventory files

| File | Change | Reason and scope |
|---|---|---|
| `docs/20261107_ONPREM_DOCUMENT_CONFIGURATION_REVIEW.md` | New detailed review with 17 correction groups, configuration additions, a safe configuration-recreation example and environment-manager findings. | Makes the approved documentation's code mismatches and unsafe instructions explicit before customer delivery. It proposes manual edits; it does not imply that they have already been applied. |
| `scripts/audit_onprem_configuration.py` | New reproducible names-only source inventory. Reads tracked code/public templates and an explicit approved-revision deployment overlay. | Records variable names, source locations and coverage without exporting live environment values. Separates shell/local candidates, runtime reads, container bindings and document-only names. |
| `scripts/test_configuration_inventory.py` | New three-test extractor suite. | Tests multiline literal reads and source lines, Node destructuring/build-time reads, comment exclusion, escaped Compose interpolation and exclusion of example values from findings. |
| `docs/qa/20261107-onprem-configuration/environment-inventory.json` | New full structured variable/candidate inventory, source revisions and dynamic-access queue. | Complete output of the stated static scan, not a claim that all dynamic/third-party settings are resolved or required. |
| `docs/qa/20261107-onprem-configuration/ENVIRONMENT_PARAMETERS.md` | New readable full names-only inventory. | Allows inspection of manifest/template coverage and source examples without loading JSON. |
| `docs/qa/20261107-onprem-configuration/onprem-configuration.json` | New compact on-prem coverage data. | Separates approved service bindings from host/script references and manual mentions. |
| `docs/qa/20261107-onprem-configuration/ONPREM_CONFIGURATION_MATRIX.md` | New compact deployer-facing coverage table. | Provides an actionable on-prem view without blindly promoting every shell-local or upstream setting into the Git manager. |
| `docs/qa/20261107-onprem-configuration/github-configuration-names.json` | New metadata-only snapshot. | Records five repository secret names and empty repository/environment variable lists. No secret values were requested. External AWS/host/organization coverage remains separate. |
| `docs/qa/20261107-onprem-configuration/approved-documents/*.txt` | New extracted content of the three approved manuals. | Enables traceable content review against the exact approved source without overwriting local manuals or relying on the PR description. |
| `docs/qa/20261107-onprem-configuration/approved-document-provenance.json` | New original-document fingerprints. | Identifies exactly which approved bytes were reviewed. |

## Proposed manual edits not yet applied

The review maps each issue to a named document and section. Required changes include removal of the MinIO-volume deletion instruction and broad lock deletion; safe secret handling for diagnostics; corrected `.env` application instructions; integration and qualification of the deployment-branch Google-font fix; withdrawal of the unimplemented local-GPU flag as a working fix; a real package-generation procedure; accessible offline asset sources; scheduler/Kubernetes variable propagation; corrected model endpoint names; coherent architecture and registry qualification; real object-store backups; and explicit remote-support authorization/teardown procedures.

Recent image-name changes must be reflected in the manuals only with a matching qualified release. The ECR destinations remain empty, GHCR/offline publication is pending, and the ignored runtime catalogue must be delivered as an updated seed asset. Source naming tests alone cannot establish those release gates.

## Verification and limitations

The inventory extractor tests passed 3/3. Targeted `git diff --check` passed. The source scan includes the current shared worktree plus selected deployment-relevant files from the approved merge, not a second full scan of that merge. It excludes private `.env` files and dependency/build/cache directories; its JSON lists skipped inputs and dynamic-access locations. Literal uppercase names are inventoried; dynamic names and externally supplied framework/plugin settings still require review.

No Word file was reauthored, so no Word render/visual approval is claimed. No live on-prem setup, GPU/cluster workflow, storage migration or remote-support tunnel was executed. Repository/environment metadata checks do not establish the contents of AWS Secrets Manager or host-managed files.

## Earlier image migration audit recorded in this session

The existing migration ledger was updated separately in `docs/20261107_IMAGE_NAME_MIGRATION_LEDGER.md`. Local naming/integrity tests passed 11/11, including exact verification of 895 catalogue cells, full tool-search content and the 32 restored historical-file hashes. The image copy failed before publication on an ECR API connect timeout; a names-only registry inventory confirmed all fourteen destinations were empty. A separate static runner credential-permission defect remains open. These are not on-prem deployment passes.

## Rules for subsequent manual updates

For every actual Word/manual edit, append the source hash, output hash, document/section, original instruction, replacement, reason, relevant code revision, validation result and any remaining qualification to this log. Preserve the approved original. Render and inspect changed Word outputs before delivery. Never silently convert an unimplemented configuration option into a supported claim or mark an unexecuted deployment test as passed.

## Follow up branch correction on November 7

User requested verification against dedicated on-prem branches and the colleague's next-phase implementation. Live remote heads were checked. `feat/aliyun-demo-deploy` had advanced from the cached `4a5227569` to `d9ae8cfee`; fetching that branch updated Git objects/remote tracking only, not working files. Next-phase remained at `79c0421d9`.

Changed the review's Google-font finding from an implementation absence to the precise state: implemented on the deployment branch, not merged to next-phase, not propagated by either reviewed Compose configuration, and not execution-qualified here. Added a branch-reconciliation section that explicitly recognizes the colleague's existing local/Slurm/Kubernetes, storage, ARM64-related and remote-support implementation. The source gap for cluster variables remains a Compose injection issue, not a claim that cluster executors do not exist.

Added `scripts/audit_onprem_branches.py` and its generated `branch-reconciliation.json` to record live branch SHAs, ancestry, selected-file fingerprints, executor/flag presence, Compose mappings, packager existence and diagnostic export patterns. Head ancestry is labelled separately from feature equivalence. The original full inventory remains a baseline-scoped scan; the new artifact records later branch implementations rather than silently rewriting the old evidence.

The three approved Word originals remain unchanged. No code merge, deployment, remote-support session or runtime acceptance test was performed. This correction supersedes any earlier wording implying that the Google-CDN handler had not been implemented anywhere.
