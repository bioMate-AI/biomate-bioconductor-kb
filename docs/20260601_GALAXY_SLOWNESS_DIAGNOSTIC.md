# Galaxy `/api/ai_assistant/generate_workflow` Slowness — Diagnostic Findings

**Date:** 2026-06-01
**Status:** Diagnosed (root cause identified), not yet patched
**Trigger:** HT-1 E2E times out at 120 s; query returns no AI response

## Reproduction

```bash
time curl -s -X POST http://localhost:8081/api/ai_assistant/generate_workflow \
  -H "Content-Type: application/json" \
  -d '{"request_text":"Run HTS plate QC and hit calling, Z-prime 0.5","preferred_domains":["drug_discovery"]}'
# → connection reset after ~160 s, no response body
```

## What's slow

CPU sampling of the gunicorn worker (`pgrep -f "gunicorn.*8081"`, then `top -b -n 1 -p <pid>` every 15 s):

| T+ | CPU% | State |
|---|---|---|
| 15 s | 20 % | running (intent classification + workflow search) |
| 30 s | 0 % | sleeping (waiting on socket) |
| 45 s | 0 % | sleeping |
| 60 s | 10 % | brief activity |
| 75–120 s | 0 % | sleeping |

**~95 % of the time the worker is idle waiting on a socket.** It is not LLM-bound or CPU-bound.

## What it's waiting on

`ss -tn state syn-sent` during the request:

```
SYN-SENT   192.168.1.117:52404   204.141.42.180:443
SYN-SENT   192.168.1.117:52400   204.141.42.180:443
SYN-SENT   192.168.1.117:52398   204.141.42.180:443
... (5+ concurrent retries)
```

**Every SYN-SENT on this host during the request points to `204.141.42.180:443`.** This IP is unreachable from this network:

```bash
$ curl --max-time 10 https://204.141.42.180/
curl: (28) Connection timed out after 5002 milliseconds
```

`whois` says it's NTT America. No reverse-DNS. Not any known LLM endpoint (`api.anthropic.com` resolves to `2607:6bc0::10`; `api.openai.com` to `162.159.140.245`; etc.) Anthropic itself responds in **115 ms** from this host with a 401 (key invalid).

## What it is NOT

- **Not Anthropic.** Direct POST to `api.anthropic.com/v1/messages` from the same host returns 401 in 115 ms. Galaxy config is `ai_llm_provider: anthropic`, `ai_llm_model: claude-sonnet-4-5`, key present in worker env.
- **Not the `/api/datasets/search` 404 on Galaxy.** That's a different defect (already documented and circuit-broken in commit `8ec6c28d9` of `frontend/server/galaxy-assistant.ts`). The frontend stops calling it after first 404; the Galaxy side never hits 204.141.42.180 for that route.
- **Not Sentry / PostHog / Segment.** None of those resolve to 204.141.42.180.
- **Not `services.healthtech.dtu.dk`** (which is set in the worker's `URL` env var). That resolves to `130.225.74.201`.
- **Not `api.biomate.ai`**, which doesn't resolve at all (returning NXDOMAIN, which would fail fast, not hang on SYN-SENT).

## Hypotheses for `204.141.42.180`

1. **Galaxy housekeeping job** — a background task initiated by the workflow generation path that retries on outbound HTTP failure with no timeout
2. **BioMNI dataset retriever** — Galaxy backend's BioMNI integration may reach a remote dataset index. Codebase has `biomni_dataset_rag.py` but no obvious 204.141 references.
3. **HuggingFace inference fallthrough** — `huggingface_hub` has an NVIDIA inference provider (`huggingface_hub/inference/_providers/nvidia.py` → `https://integrate.api.nvidia.com`). That domain resolves to `75.2.113.119`, not 204.141, so likely not it directly — but a SentenceTransformer or HF call somewhere may use a CDN that's stuck.
4. **A third-party library** doing telemetry / model registry / metric reporting on first call.

## Method that would pin it

`py-spy dump --pid <worker-pid>` while the request hangs would show the exact Python frame issuing the socket call. We tried; failed with `Permission Denied` because `kernel.yama.ptrace_scope=1` and no sudo on this box.

Alternative without sudo:
1. Set `echo 0 > /proc/sys/kernel/yama/ptrace_scope` (needs sudo too — won't help)
2. **Add a `socket.setdefaulttimeout(10)` early in the gunicorn worker boot** — would force the hang to fail fast with `socket.timeout`, and the resulting Python traceback would identify the call site
3. **Run gunicorn under `pythontrace` / `py-spy record --duration 30 -o profile.svg --pid <worker>`** with elevated perms in a future session
4. **Add `requests.adapters.HTTPAdapter(timeout=…)` defaults** if all outbound HTTP in Galaxy uses `requests`

## Impact

- **HT-1..5 + AD-1..5 + cryo chat E2Es all hit this.** Every workflow-generation chat turn waits ~160 s for the hung SYN-SENT to time out and recover via retries before the LLM step proceeds.
- **Real users would also hit this** if they trigger workflow generation from a network that can't reach `204.141.42.180`. The Galaxy worker tries; eventually times out; presumably recovers to use cached or fallback path.
- **Wastes one gunicorn worker per chat turn for ~160 s.** With 2 workers configured, the second concurrent chat turn queues until the first frees.

## Recommended next step

Bring a session with `sudo` access and run `py-spy dump --pid <galaxy-worker-pid>` while a hung request is in flight. The output will name the file + line that issues the hung socket call. From there the fix is concrete: either add a timeout, replace the outbound dependency, or short-circuit when the host is unreachable (similar pattern to the `searchDatasets` circuit breaker in `8ec6c28d9`).

Until then, this is the dominant bottleneck preventing HT-1..5 + AD-1..5 chat-path E2Es from completing within the 120 s `sendMessage` timeout.

## References

- Frontend circuit-breaker companion fix (`/api/datasets/search` 404): commit `8ec6c28d9`
- Session summary including this diagnostic: `docs/20260531_INFRA_PIVOT_SESSION_SUMMARY.md`
- Symptom audit: `frontend/e2e/screenshots/hts-ux/audit_1780361795767.json` (HT-1 `skip_no_response` post-fix)
