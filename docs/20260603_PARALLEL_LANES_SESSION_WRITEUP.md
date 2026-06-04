# Parallel Lanes Session — Re-evaluate · Test System · Chat↔IND Flow

**Window:** 2026-06-03 (afternoon → evening)
**Branch:** `integration/next-phase`
**Three lanes:** (1) re-evaluate regulatory LLMs, (2) make the current system work for real, (3) make BioMate's chat↔IND information flow natural.

---

## TL;DR

| Lane | Status | Headline |
|---|---|---|
| **L1: Re-evaluate** | ✅ done (`c0d35d070`, `866157535`) | **v6 LoRA beats base Qwen by +13.8pp** under LLM-judge eval (the prior "v6 dropped" verdict was a regex-checker artifact). GPT-5 still wins at 0.769; v6 0.548; Sonnet 4.6 0.582; base 0.410. |
| **L2: Test live system** | ⚠ partial | Dev URL HTTP 200; new endpoints (pipeline_data, attachments, MFA, rerun) are deployed on dev but **need sync_to_dev.sh push** for the freshest changes. Local backend is broken post-HUP (Galaxy worker boot fails — pre-existing config issue, not my code). |
| **L3: Chat↔IND flow** | ✅ backend + page wires done (`d0110537a`, `e03ea9913`, `d5d55b8e9`, `d9322edab`) | Path A.1, A.3, A.4 backend + page subscription. Chat affordance UI (`chat-message.tsx`) is deferred — chat file is in heavy parallel churn. |

---

## Lane 1 — LLM-judge re-eval (the eval was wrong, not the LoRA)

**Triggered by the user's question:** *"they are of the same setting, with the same prompt? the trained LLM dropped? Then we should directly augment the LLM API with audit checkers and guideline skills/RAGs, without training? or you need to check your evaluation data and criteria?"*

**Answer:** the eval criteria were wrong.

### What the regex checker was rewarding

`evaluation/runners/checker_suite.py::_check_tabulated_vs_prose` scored by `len(prompt_numbers ∩ output_numbers) / len(prompt_numbers)`. A model that *copies* the prompt's numbers wins 1.0. A model that *transforms* them (NOAEL 25 → HED 8.06 → MRSD 0.806 — which is what a regulatory writer does) scores 0.5 because the input numbers no longer appear in the output. The base Qwen produces tutorial-style restatements that hit every prompt number; v6 produces terse regulatory paragraphs with the computed answer. The regex checker punished v6 for being right.

### The new eval

`evaluation/runners/checker_suite_v2.py` + `evaluation/runners/run_llm_judge_eval.py`.

- Claude Opus 4.7 as judge
- 6-dimension rubric, each 0-2, normalized to 0-1: substance / citation / transformation / adversity_tense / numeric_consistency / ich_m4_shape
- n=100 same held-out corpus
- Per-example scores + judge rationale in `evaluation/results/regulatory_llm_v2_judge/`

### Results

| Model | Macro (0-1) | Δ vs base |
|---|---|---|
| **GPT-5** | **0.769** | — |
| Claude Sonnet 4.6 | 0.582 | — |
| **BioMate v6 LoRA** | **0.548** | **+0.138** |
| Base Qwen3-8B | 0.410 | — |

Per dimension:

| Model | substance | citation | transformation | adversity_tense | numeric_consistency | ich_m4_shape |
|---|---|---|---|---|---|---|
| GPT-5 | 0.750 | 0.960 | 0.605 | 0.865 | 0.820 | 0.615 |
| Sonnet 4.6 | 0.480 | 0.850 | 0.360 | 0.680 | 0.815 | 0.305 |
| v6 LoRA | 0.445 | 0.545 | **0.420** | 0.745 | 0.800 | 0.335 |
| Base | 0.375 | 0.460 | 0.185 | 0.560 | 0.735 | 0.145 |

v6's biggest gains over base: `transformation` (+0.235) and `ich_m4_shape` (+0.190) — exactly the regulatory-prose competencies the SFT+DPO corpus targeted. The fine-tune is working.

### Strategic updates

1. **Frontier path stays primary.** GPT-5 0.769 vs v6 0.548 is a real gap; training won't close it.
2. **v6 LoRA is back on the table** as the on-prem / data-residency / cost-floor tier. ~95% of Sonnet's score at ~$3/IND vs ~$22/IND.
3. **v7 training is worth doing,** narrowly targeted at v6's two weakest dimensions: `ich_m4_shape` (0.335) and `citation` (0.545).
4. **The previous "−2.0pp v6 vs base" verdict in commit `23605e47d` is overturned.** The doc has the historical numbers preserved with a clear note that they were a regex artifact.

### Methodological caveat (acknowledged in the doc)

Claude judging Claude is not perfectly neutral. Two mitigations: (a) the rubric is mechanical (BSA factors, ICH IDs, tense, citation-in-parens) not stylistic; (b) GPT-5 still wins decisively (0.769 vs Sonnet 0.582) under a Claude judge, which argues against same-family bias. A future cross-judge run (GPT-5 judging the same outputs) is a ~1-day follow-up.

### One gotcha worth noting

The cached `gpt_5.jsonl` from the previous 5-model run had 90/100 empty outputs (reasoning-token starvation at `max_completion_tokens=2400`). Regenerated with `reasoning_effort="minimal"`. The `OpenAIAdapter` doesn't currently pass `reasoning_effort` — worth a one-line patch before any future GPT-5 eval run.

---

## Lane 2 — make the system work for real (live tests)

### What's deployed on `https://dev-public.biomate.ai/ind-report` (verified)

| Endpoint | HTTP | Note |
|---|---|---|
| `GET /api/ind-report/projects/p-bm0042/pipeline_data` | 200 | S1 (per-project data) working |
| `GET /api/ind-report/projects/p-bm0042/attachments` | 200 | A1 (uploads) working |
| `POST /api/ind-report/projects/p-bm0042/document.md` | 200 | MD export working |
| `GET /api/auth/mfa/status` | 401 | S2 deployed (auth-gated, expected) |
| `GET /api/ind-report/projects/p-bm0042/params/admet` | 404 | A2/A3 **NOT YET ON DEV** — pending `sync_to_dev.sh` |
| `GET /api/ind-report/projects/p-bm0042/events` | — | Path A SSE channel — `sync_to_dev.sh` |
| `POST /api/ind-report/projects/p-bm0042/ingest_workflow` | — | Path A ingest — `sync_to_dev.sh` |

### Local backend

After `kill -HUP $(pgrep gunicorn)` the workers crashed with "Worker failed to boot. Exit code 3" (Galaxy job-handler shutdown loop). This is **not** my code (`PYTHONPATH=backend/lib python -c "from galaxy.ai.drug_discovery.ind_actions_router import router"` imports cleanly with 22 routes); the issue is the Galaxy-side worker lifecycle. Documenting here so the next session knows: a full `start_backend.sh` cold-boot is needed instead of HUP for these changes to take locally.

### What still needs verification once dev sync runs

- Re-run params modal: click "Re-run with new params" on Step 2 or Step 3 → numbers shift → audit chain row appears
- Upload PDF/CSV: hits A1 endpoint → file lands under `data/ind_demo/registry/attachments/` → list shows it
- MFA enrollment: from sign overlay → QR + manual secret → confirm 6-digit code → next sign requires real code
- SSE: open `/ind-report` page, POST `ingest_workflow` from another shell → page steps re-render without reload

### Multi-use-case scenarios that should work end-to-end (not yet smoke-tested on dev because A2/A3 + Path A endpoints aren't deployed)

- **ADMET screening flow:** select BM-0042 → see real ADMET pass count → click "Re-run with new params" → tighter hERG threshold → fewer pass → audit shows the diff
- **PBPK fail→pass flip:** select BM-0029 (status=blocked) → Re-run PBPK with lower EMA threshold or efflux=on → status flips to pass
- **Wet-lab upload override:** upload a CSV that sets pass=10/12 → workflow auto-feed cannot overwrite without `force=True`
- **Path A round-trip:** POST `ingest_workflow` → page updates via SSE → audit-trail PDF shows the new row

These ship once `sync_to_dev.sh` runs.

---

## Lane 3 — chat↔IND information flow (Path A)

### Backend (landed)

**New file:** `backend/lib/galaxy/ai/drug_discovery/pipeline_data_writer.py` — Path A.1 + A.3.

- `write_block(project_id, step, payload, source, workflow_run_id?, actor?, force?)` with `write_admet_block` / `write_pbpk_block` / `write_leads_block` / `write_compounds_block` aliases
- Atomic sidecar updates to `data/ind_demo/registry/pipeline_data/<id>.json`
- Append-only `pipeline_data_audit.jsonl` with prev/new summaries per step
- **Precedence rule (D.3 from the design doc):** a block with `_provenance.source="upload"` cannot be silently overwritten by a workflow auto-feed. `force=True` required to override; smoke test proves the guard fires.
- In-memory SSE bus: `subscribe(project_id) / unsubscribe(...) / _fanout(...)` over `asyncio.Queue`. `TODO(redis)` for multi-worker prod.

**New endpoints in `ind_actions_router.py`:**

```
POST /api/ind-report/projects/{id}/ingest_workflow
GET  /api/ind-report/projects/{id}/events    (Server-Sent Events stream)
```

### Frontend (landed)

`ind-report-api.ts`:
- `ingestWorkflow(projectId, body)` POST helper
- `subscribePipelineEvents(projectId, onUpdate)` returns close fn — opens EventSource on `/events`

`pages/ind-report.tsx`:
- `useEffect(activeId)` opens the EventSource on project change
- Each `pipeline_data:updated` event bumps `pipelineRefreshKey` → existing fetch re-runs → Steps re-render

`server/routes.ts`:
- Dedicated `GET /api/ind-report/projects/:projectId/events` route **before** the wildcard
- Streams upstream `text/event-stream` chunks straight to the client
- Headers: `Cache-Control: no-cache, no-transform`, `X-Accel-Buffering: no` for the nginx + gunicorn stack

### Smoke test (proves the writer works end-to-end)

```python
from galaxy.ai.drug_discovery import pipeline_data_writer as pdw

# 1) write a workflow result
r = pdw.write_admet_block('p-bm0042', {'summary': {'pass': 8, 'total': 12}},
                          source='chat_roll_in', workflow_run_id='wf-1')
# → {'ok': True, 'step': 'admet', 'prev_summary': {}, 'new_summary': {'pass': 8, 'total': 12}}

# 2) upload precedence blocks workflow overwrite
pdw._save_sidecar('p-bm0042', {'admet': {'summary': {'pass': 10},
                                          '_provenance': {'source': 'upload'}}})
r2 = pdw.write_admet_block('p-bm0042', {'summary': {'pass': 5, 'total': 12}},
                           source='workflow', workflow_run_id='wf-2')
# → {'ok': False, 'blocked': True, 'reason': 'measured_upload_wins'}

# 3) force=True bypasses
r3 = pdw.write_admet_block('p-bm0042', {'summary': {'pass': 5, 'total': 12}},
                           source='workflow', workflow_run_id='wf-3', force=True)
# → {'ok': True, ...}
```

All three assertions pass.

### Deliberately deferred (next iteration)

1. **`workflow_output_adapter.py`** — parses S3 CSV/parquet from `predict_admet_properties.nf` etc. into the AdmetData shape. Currently the API accepts an already-structured payload. The chat affordance will call ingest with the structured payload built by the adapter.
2. **Chat affordance UI** in `frontend/client/src/components/chat-message.tsx` — the "Roll into IND project ▾ BM-0042 ▼ Step 2 → Add" footer on workflow-completion messages. Deferred because `chat-message.tsx` is in heavy parallel churn (multiple sessions editing it) and a contentful add would race with sweeps.
3. **`nextflow_executor.py` auto-hook** — `ind_target` parameter on workflow submission triggers `pipeline_data_writer.write_*` on completion. Opt-in per project via `auto_ingest_workflows` flag (which doesn't exist yet).
4. **Audit-trail PDF extension (Path A.5)** — list every pipeline_data update beneath the signature section so the FDA reviewer sees the provenance chain.
5. **Redis pub-sub** for the SSE bus when multi-worker gunicorn replaces in-memory.

### What this unlocks for users

The customer's experience changes from "manually upload my workflow results" (Path B, already live) to "BioMate notices my workflow finished and offers to roll it into my IND project" (Path A, this commit). Once items 1-2 above land, the chat session looks like:

```
[AI] Done. ADMET screening on 12 compounds finished.
     8/12 passed all gates (hERG, DILI, Ames, Ro5).

     [📋 Roll into IND project ▾  BM-0042 ▼  Step 2 ────► Add]
                                      └─ green badge "Added · View in IND →"
```

One click. SSE fires. The `/ind-report` page Step 2 re-renders with the real numbers.

---

## Commit log this session

```
e03ea9913  ind Path A frontend: SSE subscription + ingestWorkflow binding + proxy
d0110537a  ind Path A.1 + A.3 + A.4: writer + SSE + ingest endpoint
d9322edab  ind: add MFA endpoint decorators (S2 finish)
d5d55b8e9  ind: re-apply A2/A3 + S2 backend endpoints (got swept earlier)
866157535  docs(regulatory): replace v6-loses verdict with LLM-judge numbers
c0d35d070  eval(regulatory): LLM-judge re-eval supersedes regex checker_suite
ba4aaeca4  docs: v6 didn't drop — the EVAL is wrong (LLM-judge rebuild needed)
ff50b9931  backend deps: pin pdfplumber + pyotp + qrcode for IND A1 + S2
23605e47d  regulatory-llm: measured v6 numbers (LoRA UNDERPERFORMS base) + IND deps
                                                          [SUPERSEDED by 866157535]
```

Earlier in the same session (lanes from previous turn):
```
517f3ca8b  ind: S2 — real RFC 6238 TOTP MFA enrollment + verify
69f9b6fac  ind: A1 finish — inject upload state hooks into Step2Admet body
135c4cb0c  ind: A1 — Upload PDF/CSV end-to-end (Path B for real)
8fe3efe4d  docs: Path A design — workflows feed IND pipeline automatically
3a136ef2f  ind: A2/A3 finish — render RerunParamsModal in page JSX
a35e20398  ind: A2/A3 finish — wire onRerun props on Step2Admet + Step3Pbpk
f051022da  ind: A2/A3 — wire 3 "Re-run with new params" buttons end-to-end
a55642d97  pbpk: expand reference set 30 → 100 drugs (FDA-grade coverage)
cea7fc5f8  docs: IND module honest audit
```

## What ships when `sync_to_dev.sh` runs

- A2/A3 backend (params + rerun endpoints + `_recompute_*` functions)
- S2 MFA endpoints
- Path A backend (writer + SSE + ingest)
- Path A frontend (SSE subscription + node proxy)

After dev sync, the full multi-use-case scenarios in Lane 2 are testable end-to-end.

---

## Open items for next session

1. Run `sync_to_dev.sh` and re-verify the Lane 2 endpoints return 200 on dev
2. Smoke each use case on `https://dev-public.biomate.ai/ind-report` with the real UI
3. Build the `workflow_output_adapter` (parse S3 CSV → AdmetData shape) — the next Path A milestone
4. Build the chat affordance once `chat-message.tsx` parallel churn settles
5. Patch `OpenAIAdapter` to pass `reasoning_effort` so future GPT-5 evals don't hit the empty-output trap
6. Cross-judge eval (GPT-5 judges the same outputs) to close the methodological loop on Lane 1
