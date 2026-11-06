# BioMate local-model implementation status — 12 September 2026

Scope: the main BioMate assistant and supporting workflows, with a maximum 32B-parameter local model. IND tasks T22/T23 and regulatory model training are excluded.

## Implemented

Local-only routing and a tool-compatible adapter connect the existing BioMate assistant loop to an OpenAI-compatible local endpoint. The configured local model handles intent, tool ranking and responses; cloud-provider overrides and fallback are disabled on these paths. Images are rejected in this text-only trial. Responses are buffered, so true token streaming is not implemented.

The task catalogue, prompt appendix and callsite inventory document the pre-implementation source snapshot. Their source hashes are historical. See [audit index](README.md), [trial runbook](../../infra/local-trial/README.md) and [episode preparation](../../evaluation/local_trial/README.md).

The episode preparation tool excludes IND data, requires reviewed provenance and evidence, and groups declared source families and exact-message duplicates before splitting. The legacy extractor marks unlinked outcomes unverified and no longer fabricates assistant replies. No reviewed production training dataset or BioMate fine-tune has been produced.

## CPU Spot trial (last observed state)

GPU Spot attempts failed capacity/quota checks. Following the user's Spot-or-CPU instruction, CPU Spot instance `i-0a9ed4897fee6ffc2` runs in us-west-2 on `r5.4xlarge` (128 GB RAM), with a $1/hour instance ceiling and scheduled termination at 20:20:03 UTC. Storage charges are separate.

Qwen/Qwen3.8-27B revision `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0` is loaded as Q4_K_M in llama.cpp. Inspection of the original 18 safetensor shards counted 27,781,427,952 stored tensor elements, passing the conservative 32B cap. This is the official post-trained assistant, not a BioMate fine-tune.

The original checkpoint and quantized inference shards are committed to the dedicated private S3 prefix. Five-minute progress backups and an IMDSv2 interruption watcher are active. Implementation, knowledge-database and full quantized-model snapshots passed actual restore/hash checks; the restored SQLite database passed integrity checking. All five GGUF shards restored successfully. See [checkpoint policy](../../infra/local-trial/CHECKPOINTS.md).

## Verification and open gates

Offline verification: 49 frontend local transport/assistant/history tests, four Python transport tests, seven checkpoint/recovery tests and seven data-preparation tests passed. Full frontend TypeScript checking passed after the transport update.

Live results: all 12 synthetic core diagnostics passed. The actual `GalaxyAssistant.generateResponse` loop called BioMate's real history handler with synthetic storage, used the returned exact run ID/status, and did not execute another workflow. It passed in 106.6 seconds with a warm model cache. The identifier JSON request through BioMate's adapter passed in 10.6 seconds. These are development diagnostics, not a scientific release benchmark.

Two initial failures are retained in `infra/local-trial/results/`: the raw server wrapped correct JSON in Markdown despite `response_format`, and the first full assistant request exceeded Node's default header timeout. The adapter now accepts only a complete object, optionally inside one JSON fence, and rejects commentary, partial/non-object/non-finite JSON without repair. A request-scoped Undici dispatcher follows the configured bounded timeout; cloud clients are unaffected. The successful loop rerun used a warm cache and therefore does not separately prove a response exceeding 300 seconds. See [live evidence](../../infra/local-trial/results/README.md).

Client readiness still requires real workflow and artifact validation, an end-to-end external-network-denial test, confirmation of all enabled retrieval/embedding dependencies, measured latency on client hardware, and a client-specific installation/rollback runbook. Training save/resume equivalence has not been exercised; the supplied callback is not yet attached to a real BioMate training job.

## Application integration update — 21:43 UTC

The actual BioMate frontend and Galaxy backend booted successfully on the isolated CPU worker; frontend root and Galaxy version health checks returned HTTP 200. A missing base-table migration and missing local knowledge-query API were implemented. The knowledge search join now uses stable tool IDs rather than unrelated FTS row IDs; three knowledge-query tests passed.

Local intent routing now uses a compact prompt (2,848 characters in the test fixture, compared with approximately 70,785 characters in the previous live request). Ten targeted frontend tests and TypeScript checking passed. Its live end-to-end quality and latency remain unverified: the model was still processing the obsolete oversized request when remote continuation was blocked.

FastQC 0.12.1 was installed on the worker. A trial wrapper is prepared locally, but actual Galaxy workflow execution and output-artifact validation have not passed. No BioMate fine-tuning run has occurred.

Automatic approval review rejected the remote upload/model-restart operation because of a Codex usage limit. No workaround was used. Consequently, the latest application changes are not confirmed backed up to S3, and full HTTP chat validation remains pending. The worker's scheduled termination time (20:20:03 UTC) has now passed; actual termination and final backup state have not been remotely verified. Earlier statements about running services and backup timers describe their last observed state, not confirmed current availability.

## Local continuation package

Prepared a real FastQC process runner and independent HTML/ZIP verifier for the synthetic 100-read, 100-base, 50%-GC fixture. Four verifier tests cover incorrect counts, ambiguous archives, missing HTML and preservation of QC failures. All 11 infrastructure artifact/checkpoint tests and seven backend local tests passed. These are offline checks; neither real FastQC execution nor Galaxy orchestration is newly claimed.

Persistent application and FastQC acceptance service definitions, model-health readiness, expanded progress/source backup coverage, and an [application recovery guide](../../infra/local-trial/APPLICATION_CONTINUATION.md) are ready. The latest source bundle was sealed locally at `/private/tmp/biomate-trial-bundle-20260912-continue` and every manifest file passed hash/size verification. It has not been published to S3. Remote execution still requires resolution of the approval-service usage limit.

## Replacement trial and data preparation — subsequent continuation

Remote operations became available again. Replacement CPU Spot worker `i-0c65bd635d94f674e` uses the same `r5.4xlarge`, $1/hour Spot ceiling and private scoped S3 role. Its verified automatic termination deadline is 2026-09-13 01:10:18 UTC. The previous worker was no longer present in the account. A fresh SSH key remains outside the repository.

The quantized model and knowledge database were restored from their committed manifests; hashes and SQLite integrity passed. The source/candidate-data bundle was published as the 100-file snapshot recorded in `infra/local-trial/resume-workspace-backup.json`, and its worker restore completed successfully. Five-minute progress backups and Spot interruption monitoring are active.

Real FastQC CPU execution passed. A real Galaxy upload, imported workflow invocation and downloaded HTML/ZIP artifact verification also passed in 36.3 seconds. The synthetic fixture produced 100 reads, length 100 and 50% GC; its QC failures are retained. Two test-fixture failures (missing annotation and incorrect input binding mode) were preserved before the successful rerun. Both successful evidence directories were published to S3. This demonstrates Galaxy execution, not LLM-driven workflow execution.

An initial actual chat classified the catalogue request in 117 seconds on CPU, then entered the research backend. Offline trial mode now bypasses that external-research route, removes external-search tools and uses a compact, evidence-grounded local response prompt. Ten frontend tests and TypeScript checking pass after the change. The test uses the actual registered `query_domain_knowledge` tool name. Its live rerun remains pending at this update.

The application/model service policies deny non-loopback IPv4 and IPv6 destinations. IPv4 probes from the restricted service cgroups timed out, while the same two destinations connected successfully in an unrestricted control. The initial probe incorrectly expected an immediate EPERM/EACCES and is retained as a failed diagnostic. Offline functional reruns are required before claiming acceptance. Other worker services, including S3 backups, are intentionally outside the application network restriction. The installed Galaxy trial tool set is upload plus the provisioned FastQC wrapper; catalogue records do not imply that other tools are installed.

Data preparation: 12,312 tool candidates, 4,198 workflow candidates and 99 repair-commit candidates are indexed with source hashes and review gates. Sixteen synthetic acceptance cases are drafted but not frozen as independent release cases. Cross-batch frozen source/message split assignments are implemented; all 11 data-pipeline tests pass. No reviewed production training examples or BioMate fine-tune are claimed. See [training and test data execution plan](TRAINING_DATA_EXECUTION.md).
