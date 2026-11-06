# BioMate CPU Spot trial evidence — 12 September 2026

This trial covers the main BioMate assistant, excluding IND. It uses the official post-trained Qwen/Qwen3.8-27B checkpoint, Q4_K_M text-only GGUF, on one r5.4xlarge CPU Spot worker. No BioMate fine-tuning has run.

| Check | Result | Evidence |
|---|---|---|
| Original checkpoint below 32B | Pass: 27,781,427,952 stored tensor elements | model-size-check.json |
| Synthetic core tasks | 12/12 pass | core-evaluation.json |
| Raw model tool round trip | Pass | live-smoke-diagnosis.json |
| Actual BioMate history-tool loop | Pass: exact run ID and failed status, no run_code call | biomate-core-live.json |
| Identifier JSON through BioMate adapter | Pass: exact accession/platform, no cloud fallback | biomate-json-live.json |
| Quantized model recovery from S3 | Pass: manifest SHA and all file hashes, five GGUF shards | quantized-restore-result.json |
| Real scientific workflow execution | Not tested here | Still a client-release gate |
| Fine-tuning checkpoint/resume equivalence | Not run | Callback/offline tests only |

The actual assistant test uses BioMate's prompt, protocol adapter and history handler with synthetic storage. Other tool handlers are disabled in the fixture. It does not demonstrate a deployed application/database or successful scientific workflow.

Latency: the successful actual assistant loop took 106.555 seconds with a warm model cache. The JSON adapter check took 10.564 seconds. The 12 short cases had a 20.350-second median; the 314.519-second maximum includes waiting behind a concurrent long request. These are diagnostic timings, not an isolated performance benchmark. The CPU configuration is useful for functional testing and may be too slow for a client demo.

## Initial failures and fixes

`initial-live-smoke.json` and `live-smoke-diagnosis.json` preserve the raw endpoint's JSON-mode failure. The response contained the correct object in a Markdown fence. The endpoint itself still fails the strict raw JSON smoke. BioMate now accepts exactly one complete JSON object, optionally enclosed in one JSON fence; it rejects surrounding commentary, arrays/null, malformed/truncated output and non-finite numbers. It removes only the fence/outer whitespace and does not repair or rewrite values. Frontend and Python regression checks cover the observed behavior. The live adapter check passed with the same identifier prompt.

`initial-biomate-live.json` preserves the first failed real-loop result. Its test process recorded UND_ERR_HEADERS_TIMEOUT while waiting for CPU prompt processing. A request-scoped Undici Agent now aligns header/body deadlines with the configured timeout, without altering global clients. The [official dispatcher documentation](https://github.com/nodejs/undici/blob/main/docs/docs/api/Dispatcher.md) describes these timeout controls. The successful rerun used a warm cache and did not itself exceed 300 seconds; no separate long-duration timeout benchmark is claimed.

The initial server smoke/check service therefore remains failed. Do not relabel it green because the separate application compatibility checks passed.

## Recovery pins

- Model revision: `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0`.
- llama.cpp revision: `3057bb66c86c46d5781e50e85462a760ba7d1feb`.
- Quantized snapshot manifest and SHA256: `quantized-backup-receipt.json`.
- Python runtime packages: `python-environment.txt`; serving itself uses the compiled llama.cpp binary.
- Model snapshot type: inference artifact, not a full optimizer/training checkpoint.

Restore instructions and limitations are in ../RESUME.md and ../CHECKPOINTS.md. The worker is scheduled to terminate at 20:20:03 UTC on 12 September 2026; S3 artifacts persist.
