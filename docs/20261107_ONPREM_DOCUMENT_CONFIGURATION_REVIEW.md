# On premises deployment documentation and configuration review

The three Chinese manuals approved in [PR 327](https://github.com/bioMate-AI/biomate/pull/327) need corrections before the next customer delivery. The most urgent issues are unsafe recovery instructions, configuration changes that do not reach running containers, and a diagnostic bundle that can disclose secrets. The recent image-name migration also needs a coordinated release update across manuals, image packages, the workflow catalogue and installer.

Reviewed baseline: approved merge `79c0421d90ff86f5973513a0360677bd72df390c`, including remote-support changes from PR 325. The shared local branch does not contain all those merged changes. Its current files were examined separately; no pull, reset, checkout or merge was used to overwrite the worktree. The Word review covers content and configuration contracts, not rendered layout. The three approved Word files have not been edited.

## Branch reconciliation correction

The first review did not examine the newer head of the dedicated deployment branch. A follow-up live remote check found `feat/aliyun-demo-deploy` at `d9ae8cfee6eb52ca9e5f1a9eda532162c5cd8119`, while `integration/next-phase` remains at `79c0421d90ff86f5973513a0360677bd72df390c`. The cached deployment branch was stale and was fetched for read-only inspection; no working files were replaced.

The colleague's substantial on-prem implementation is already present in next-phase: local execution, Slurm/Kubernetes executor generation, storage modes, ARM64-related changes and remote-support tooling. The cluster finding below concerns settings not propagated by the supplied Compose configuration, not absence of the executor implementation. The latest deployment branch has the same reviewed deployment/runtime files as next-phase except for a sixteen-line addition in `frontend/server/vite.ts`.

The Google-CDN flag is **implemented on the deployment branch**, rather than absent from all code. Commit `d9ae8cfee` is not in next-phase. Neither reviewed Compose version passes `DISABLE_GOOGLE_FONTS` into the frontend, and restart still does not reload its environment. The feature therefore needs integration and end-to-end qualification; it should not be described as requiring implementation from scratch. Its new handler also follows `express.static()`, so qualification must exercise both `/` and deep-link routes rather than testing the helper alone.

The branch comparison is recorded in `docs/qa/20261107-onprem-configuration/branch-reconciliation.json`. Older on-prem branch heads are included as selected-file comparisons. A branch head not being an ancestor does not prove its features are missing: squash/cherry-pick integration can preserve the implementation under other commits. No running host/image version was established by this branch check.

## Corrections required before customer use

| Priority | Document and section | Finding | Required correction |
|---|---|---|---|
| Critical | Delivery checklist A7, following A8 | Recommends deleting the MinIO volume to resolve credential mismatch. | Remove this recovery path. Preserve the object store, verify the configured endpoint and credentials, and use a controlled credential-rotation procedure with backup. Never delete research data to repair authentication. |
| Critical | Remote support section 2 | Describes a redacted bundle, but `collect_inspect()` saves raw Docker inspect JSON. `Config.Env` can contain passwords, tokens and database URLs. The separate environment-summary filter also does not match every sensitive name, such as `EMAIL_PASS` or credentials embedded in `DATABASE_URL`. | Do not describe the bundle as safe to send. Redact structured inspect fields and logs, review the resulting bundle locally, and obtain customer authorization before transferring it. Prefer an allowlist of diagnostic metadata. |
| High | Operations sections 2, 4, 10, 11.2 and 12; checklist A1, A5 and A8 | Tells operators to edit `.env` then run `docker restart`. Existing containers retain their old environment. | Replace with the explicit Compose recreation procedure below, after confirming the variable is mapped into the affected service. |
| High | Operations 11.2; checklist A1 | `DISABLE_GOOGLE_FONTS` filtering is implemented in deployment-branch commit `d9ae8cfee`, but is absent from approved next-phase. Neither reviewed Compose version passes the flag. | Integrate the existing implementation, wire the setting to the frontend and test root/deep-link requests on the exact built image. Correct the restart instructions. A temporary container-file patch is not a durable release fix. |
| High | Operations appendix; checklist implementation step 2 | Calls `scripts/package-onprem.sh`, which is absent from the approved commit. | Supply and test the packager or replace these commands with an existing verified packaging procedure. Document the actual archive layout and filenames. |
| High | Operations offline appendix | Uses host `file:///opt/biomate-assets/...` URLs, but init containers do not mount that host directory. The workflow init uses `wget`, so local-file support also cannot be assumed. | Use a reachable approved internal HTTP source or implement explicit read-only mounts and a tested local-copy path for both init containers. Include checksums and an offline installation test. |
| High | Operations 5.1 GPU | Describes `NEXTFLOW_DOCKER_GPU_OPTIONS` as consumed by the executor. No literal runtime consumer or Compose mapping exists in the reviewed code. | Mark local GPU setup unqualified until device access and per-task GPU options are implemented and tested. Do not publish an inert setting as a working solution. |
| High | Operations Slurm and Kubernetes instructions | Executor code reads `SLURM_*` and `NXF_K8S_*`, but the approved Compose backend environment does not pass those settings. | Add and verify the selected settings through the actual deployment path; document scheduler clients, credentials, shared storage, service accounts and registry access. `.env` alone is insufficient. |
| High | Checklist acceptance 3 | Refers to `OPENAI_API_BASE_URL`; the shipped local-model contract uses `LLM_API_URL`, `LLM_API_KEY`, `LLM_MODEL` and provider selection. | Use the actual configuration names and validate the selected model from both frontend and backend services. |
| High | Checklist A3 and operations 11.5 | Checklist deletes all matching lock files recursively; the operations manual identifies one involucro lock. | Replace broad deletion with the exact validated lock path, stop the owning service, verify the lock is stale, and preserve evidence before recovery. |
| High | Both manuals, archive and image instructions | Recently renamed image repositories and installer override names are not reflected in the approved documents. Neutral repositories currently contain no copied images. | Update wording only as part of a verified release: image digests/tags, offline tar names, installer override, CI build paths, seed catalogue and workflow archive must agree. Do not instruct customers to pull unpublished references. |
| Medium | Checklist ports; operations MinIO console access | Tells remote users to browse port 9001, while approved Compose binds it to loopback. | Document an authorized SSH tunnel or secured admin proxy. Do not expose MinIO administration broadly just to make the example work. |
| Medium | Backups in both manuals | Checklist names `/app/biomate/data/minio`, but Compose uses a named volume. Operations backup omits object storage and the full configuration/key material needed for recovery. | Back up the actual named volume or supported object-store export, PostgreSQL, workflow catalogue, configuration, encryption keys, model assets and workflow definitions; rehearse restore. |
| Medium | Hardware and architecture sections | Blanket complete ARM64 support and fixed QEMU slowdown figures exceed the per-image evidence established by this audit. GPU resource-name changes alone do not prove accelerator/software compatibility. | Publish per-image architecture and CPU/GPU qualification with tested workflows and constraints. Keep model memory estimates tied to quantization, context and concurrency. |
| Medium | Remote support sections 1, 3 and 4 | Introduces one-time frp tokens while later documenting a shared quarterly-rotated token; auth-key lifetime is presented as a session teardown guarantee. | Describe the implemented shared-token design honestly; add explicit stop/revoke verification, session authorization, audit logging and expiry enforcement. Review tunnel variants separately before recommending them. |
| Medium | Remote support and troubleshooting | Recommends sending logs to chat/email and using external AI tools on customer hosts; several commands print API keys or complete database URLs. | Add hospital data-handling approval, names-only credential checks, redaction and retention rules. No customer data or credentials should leave the approved boundary by default. |
| Medium | Operations introduction and document sources | Links to an absent `ONPREM_DELIVERY_CHECKLIST.md`; the Word and Markdown operations versions also differ, including the Google-font and storage instructions. | Establish a versioned source of truth and generate/reconcile all delivered formats. Verify internal links and record the code/image release each manual describes. |

## Correct procedure for applying configuration

For settings already mapped by Compose, use the deployment directory and its explicit environment file:

```bash
cd /app/biomate
docker compose --env-file .env -f docker-compose.onprem.yml \
  up -d --no-deps --force-recreate galaxy-backend frontend
docker compose --env-file .env -f docker-compose.onprem.yml ps
```

Run this during a planned service window and choose only the affected services. Storage-service credential rotation has additional coordination requirements; this command is not a storage migration procedure. Verify settings with names-only presence checks and a functional upload/run/output-preview test, not by printing secret values. Build-time `VITE_*` settings require a correctly built replacement frontend image; container recreation cannot change a value already embedded in the browser bundle.

Docker explicitly documents that environment changes are not applied by restart: [Compose restart reference](https://docs.docker.com/reference/cli/docker/compose/restart/).

## Configuration additions to the operations manual

### Profiles and ownership

Separate local on-prem, offline on-prem, external-object-storage, Slurm, Kubernetes and cloud Batch profiles. Do not reuse the cloud manifest's required Anthropic, AWS and Lago settings as universal on-prem prerequisites. For each setting list its owner, purpose, conditional requirement, secrecy, source, consuming service, how it is injected, validation command and whether it requires image rebuild or container recreation.

Values belong in the customer's approved secret/configuration manager. Repository files should carry names and safe examples only. Do not upload a customer configuration or private data to BioMate GitHub as a side effect of completing the catalogue.

### Local models and provider selection

Document `LLM_API_URL`, `LLM_API_KEY`, `LLM_MODEL`, `GALAXY_AI_LLM_PROVIDER`, `GALAXY_AI_LLM_MODEL` and `OLLAMA_BASE_URL`, plus provider-specific keys only for enabled providers. Include model provisioning, model identifier, tool-calling compatibility, timeout/network constraints, fallback policy and whether any request can leave the hospital network. The manual currently omits the default `openai_compatible` option from its supported-provider list.

### Storage and output access

Document `S3_ENDPOINT_URL`, `S3_FORCE_PATH_STYLE`, `S3_BUCKET_NAME`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, conditional session-token handling, `AWS_DEFAULT_REGION`, `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD` and `NEXTFLOW_WORK_DIR`. Distinguish unset endpoint, explicitly empty endpoint and a configured MinIO/OSS endpoint; the approved Compose deliberately uses `${S3_ENDPOINT_URL-http://minio:9000}`, not `:-`, so empty and unset have different meanings.

Do not treat the approved OSS frontend/Nextflow path-style wiring as proof that every S3 client or connector supports every storage provider. Validate upload, download, output preview, presigning, workflow staging and custom bucket handling separately. Match host and container work-directory mounts; changing the environment variable does not rewrite fixed Compose bind mounts.

### Execution and image distribution

Document `NEXTFLOW_EXECUTOR`, `NEXTFLOW_USE_AWS`, `DOCKER_DEFAULT_PLATFORM`, `DOCKER_GID`, `BIOMATE_DOCKER_NETWORK`, `BIOMATE_LOCAL_REGISTRY`, `BIOMATE_BIOC_CONTAINER`, `BIOMATE_ADMET_CONTAINER` and the neutral installer override `BIOMATE_WORKFLOW_TOOLS_IMAGE`. The override replaces the old installer setting in the pending local migration; do not claim the approved release already includes it. Document internal container-visible registry addresses separately from host-visible addresses.

For supported cluster profiles, cover `SLURM_PARTITION`, `SLURM_QOS`, `SLURM_ACCOUNT`, `SLURM_WORK_DIR`, `NXF_K8S_NAMESPACE`, `NXF_K8S_STORAGE_CLAIM`, `NXF_K8S_STORAGE_MOUNT`, `NXF_K8S_SERVICE_ACCOUNT`, `NXF_K8S_PULL_POLICY` and `NXF_K8S_GPU_RESOURCE`. These need actual Compose/service propagation and runtime qualification. Changing `NXF_K8S_GPU_RESOURCE` alone does not establish GPU scheduling or compatibility. Do not add `NEXTFLOW_DOCKER_GPU_OPTIONS` as a supported knob until its missing consumer is resolved.

### Security, identity and operations

Cover PostgreSQL and MinIO credentials; `JWT_SECRET`, `SESSION_SECRET`, `GALAXY_API_KEY`; conditional `FIELD_ENCRYPTION_SECRET`, `MFA_ENCRYPTION_SECRET`, `ENCRYPTION_KEY` and `CSRF_SECRET`; `APP_URL`, `FRONTEND_URL`, `CORS_ORIGINS`, `FORCE_HTTPS`, `ENABLE_HSTS`; SMTP and `WORKFLOW_NOTIFY`; license provisioning and key custody. Document which are service-internal, customer-managed, or BioMate release-team-only. Do not assume the name `BIOMATE_LICENSE_SECRET` establishes a safe license-signing/verification architecture; review custody explicitly.

Add an egress/allowlist matrix, offline model and database provisioning, certificates/proxy/CA requirements, Docker-socket privilege boundary, backup encryption, audit retention, resource/concurrency controls and support-session approval. Mark unknown requirements as qualification work rather than unsupported guarantees.

## Git environment manager coverage

`deploy/biomate.env.manifest` lists 71 names. It describes a cloud-oriented deployment, not the complete product configuration surface. Its header's claim that changing this file is sufficient no longer describes every active deployment path: `scripts/deploy.sh` invokes `load_env_from_secrets.sh`, whose loader imports keys present in the external JSON secret rather than filtering by this manifest.

Names-only GitHub metadata on November 7 showed five repository secrets (`ALIYUN_AK`, `ALIYUN_SK`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `ECS_ROOT_PASS`), no repository variables, and no secret/variable entries in the `development` and `test` environments. This is not proof that runtime values are absent: AWS Secrets Manager, organization inheritance and host-managed configuration are separate sources. No secret values were requested, and no remote settings were changed.

The bootstrap script's secret classification is an explicit allowlist. New sensitive names such as `LLM_API_KEY`, `DEEPSEEK_API_KEY`, `ZHIPU_API_KEY`, `OPENROUTER_API_KEY`, `MINIO_ROOT_PASSWORD`, `BIOMATE_LICENSE_SECRET` and `AWS_SESSION_TOKEN` must receive an explicit secret classification before adding them to a manifest used by that uploader. Otherwise an added name may be uploaded as a public GitHub Variable. Do not blindly append the generated inventory to the production manifest.

Recommended follow-up: establish a typed names-only catalogue with deployment profiles and secrecy classifications, generate profile templates/validation from it, and make each loader's behavior explicit. Preserve host-only values and validate selected profiles without forcing unrelated cloud integrations.

## Inventory and verification

The generated full inventory and compact on-prem coverage matrix are under `docs/qa/20261107-onprem-configuration/`. Each entry records names and source locations, current-worktree versus approved-commit evidence, manifest coverage, template coverage and conservative secret review. Container bindings are separate from host inputs. Test-only, upstream, historical and shell-local references are labelled rather than treated as mandatory product settings.

The current scan contains 3,435 distinct names from 29,524 source inputs, of which 2,161 have literal runtime-read evidence somewhere in the scanned source. The compact on-prem matrix contains 124 names/candidates. Across the approved and current public on-prem templates, 47 names are absent from the 71-name Git manifest. These include optional and release-team-only settings, plus the superseded installer override; they are not 47 newly mandatory customer settings. The full JSON retains 72 dynamic-access locations for follow-up.

Those counts describe the original worktree/approved-merge inventory. The subsequent branch comparison is a separate artifact, not a full re-scan of every branch. In particular, the original `DISABLE_GOOGLE_FONTS` row has no runtime evidence in that baseline; the deployment-branch implementation is positively recorded in `branch-reconciliation.json`. Do not read the original row as a claim that no branch implements the flag.

The extraction is static: dynamic variable names and external dependencies remain an explicit review queue. It is not a live environment export or proof of complete third-party configuration coverage. The three extractor tests cover multiline reads, source lines, destructuring/build-time access, comment exclusion, escaped Compose references and non-disclosure of values. No on-prem deployment or container execution was performed for this documentation review.
