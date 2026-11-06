# BioMate local-model trial implementation

Status: Qwen3.8-27B Q4_K_M served successfully on CPU Spot with verified S3 model recovery. The scheduled worker termination time has passed; current availability is unverified. All 12 core diagnostics, the actual BioMate history-tool loop, and the live BioMate JSON adapter check passed. **Not client-ready: scientific acceptance, complete external-call audit, client latency and deployment remain outstanding.** No model has been trained by this work. See [live evidence](results/README.md) and [implementation status](../../docs/20260912_onprem_llm/IMPLEMENTATION_STATUS.md).

**Scope: BioMate main assistant and workflows. IND model training and regulatory drafting/audit are excluded by user instruction.**

## Local inference configuration

Apply `trial.env.example` to both Node and Python processes, then restart them. Set URL to the server's OpenAI-compatible `/v1` base and ORIGIN to its exact scheme/host/port. An explicit origin prevents accidental redirects/configuration drift; it is an operator trust setting, not proof of on-premise hosting. Configure network egress restrictions separately and verify them for all application workers.

The local transport forces the configured model regardless of caller model labels. The configured local model name is retained in metadata; local-only mode selects the existing tool loop through its protocol adapter. User cloud-key overrides and Gemini auto-selection do not override local mode. Missing configuration, redirects and inference errors fail without entering the shared cloud fallback chain. Non-thinking mode is requested through the checkpoint's chat template.

The main assistant uses a Messages-API compatibility adapter to retain its existing tool handlers, IDs and observations. The adapter validates the simple tool schemas used by BioMate. It buffers the model response before emitting compatibility events; true incremental token streaming is not implemented. The initial adapter rejects image/other unsupported content explicitly. Do not claim image interpretation support in this trial.

Covered paths include main intent and response generation, the assistant tool loop, shared lightweight generation, memory updates using that wrapper, frontend `llmGenerate`, backend `LLMClient`/shared fallback entry, and local construction of workflow/report helper clients. This does not prove every optional backend SDK or third-party library is local: PaperQA/embeddings and worker-specific paths require separate live checks. Keep unverified features outside the client trial until they pass. Existing external scientific data and AWS workflow dependencies are separate from LLM inference hosting.

## Compute and recovery

User decision: Spot or CPU, with checkpoints and consistent S3 backups. The CPU Spot worker was last observed running before its scheduled termination; see [checkpoint and recovery policy](CHECKPOINTS.md) and [verified backup receipt](backup-receipt.json). No on-demand GPU fallback is requested.

## GPU runtime

`bootstrap.sh` prepares a four-GPU BF16 trial. `bootstrap-single-gpu.sh` is a one-L40S FP8 alternative. Both bind inference to loopback, record the pulled image digest, and schedule shutdown after 180 minutes before downloading artifacts. EC2 **must** have `InstanceInitiatedShutdownBehavior=terminate`, as in the prepared launch request. These scripts are not a validated client installer yet.

They currently use the official Qwen3.8-27B checkpoint. Before client delivery, pin the successfully tested container digest and model commit, inspect total tensor parameter count against the 32B ceiling, download all required files, and rerun with external network access disabled. `python3 infra/local-trial/check_model_size.py CHECKPOINT_DIRECTORY` checks the conservative stored-tensor count on complete unquantized safetensors without loading weights. It rejects mixed/incomplete shards and quantized checkpoints rather than guessing their original parameter count. Loading a checkpoint is not SFT. Quantized and BF16 results must be reported separately.

The operator workstation can reach the loopback API through an SSH tunnel, without exposing port 8000:

```sh
ssh -i /path/to/test-key -N -L 8000:127.0.0.1:8000 ubuntu@INSTANCE_ADDRESS
python3 infra/local-trial/smoke.py --output /private/tmp/biomate-live-smoke.json
```

The smoke runner checks exact identifier JSON and a two-turn tool exchange on synthetic fixtures. It exits nonzero on failure and writes raw responses and latency. It is not the planned 200-case smoke suite or the locked scientific release benchmark.

## Checks performed

- Frontend local transport tests: configuration, no cloud fallback, redirects disabled, complete JSON, truncation rejection, tool IDs/results, compatible events, invalid tools/parameters and unsupported content.
- Actual `GalaxyAssistant.generateResponse` loop tested against mocked local responses and BioMate's history handler, with a cloud key present to catch accidental provider selection.
- Existing history/context handler regression tests.
- Python transport checks: wire schema, system prompt, JSON, truncation and redirects.
- Source-family split checks and legacy extractor mislabeling regression checks.
- Full frontend TypeScript check and `git diff --check`.

These listed checks are offline tests. Live evidence is tracked separately in `results/`. No scientific workflow completion, GPU performance, air-gap compliance or client acceptance is claimed.

## Spot attempt log

Authorized by user: choose an AWS Spot GPU for testing. Account used: BioMate configured account 399683337364. All attempts were one-time requests with termination on shutdown, an encrypted delete-on-termination root disk, IMDSv2 required, no instance role, and SSH restricted to the workstation's /32. No public inference ingress was requested.

Oregon attempts covered g5.12xlarge, g5.24xlarge, g6.12xlarge, g6e.12xlarge and g6e.2xlarge across multiple zones and returned insufficient capacity. Ohio attempts returned insufficient capacity for g5.12xlarge and `MaxSpotInstanceCountExceeded` for g6.12xlarge/g6e.2xlarge. Instance caps were $5/hour except one unsuccessful g6e.12xlarge attempt capped at $7/hour. No instance ID was returned by any launch.

Temporary resources created (no GPU instance):

| Region | Security group | Key-pair name |
|---|---|---|
| us-west-2 | sg-011121fdf81073ec8 | biomate-local-trial-20260912 |
| us-east-2 | sg-09228d064305d7d34 | biomate-local-trial-20260912 |

Private key remains outside the repository at `/private/tmp/biomate-local-trial-20260912`. Do not commit it. Remove these resources when the test completes or is abandoned. The user chose Spot or CPU instead of an on-demand GPU fallback. A CPU Spot worker was subsequently launched; current state is recorded in CHECKPOINTS.md and aws-instance.json.

## Remaining release gates

1. Complete live JSON/tool smoke, prompt-budget and memory/latency tests. CPU checkpoint loading and original parameter-count checks are complete. A GPU is optional for functional checks but may be needed for acceptable client latency.
2. Exercise full BioMate chat/workflow/report routes against real local services; validate every enabled feature's provider and retrieval dependencies.
3. Run independent scientific and artifact/authorization checks; disable failing features or fix them before client trial.
4. Demonstrate zero external model traffic under forced local failures and with external credentials present, including background workers and libraries.
5. Export reviewed, correctly linked training episodes; prepare grouped splits; run real SFT save/reload and compare to baseline. Do not delay a passing limited baseline pilot solely for SFT.
6. Package pinned artifacts, environment settings, startup/health checks, tested rollback and a client-specific runbook after client hardware information arrives.

## Application continuation package

See [application continuation](APPLICATION_CONTINUATION.md) for the compact-prompt rerun, persistent acceptance services, independent FastQC artifact checks, and recovery order. These latest checks are prepared locally; live application acceptance remains pending.
