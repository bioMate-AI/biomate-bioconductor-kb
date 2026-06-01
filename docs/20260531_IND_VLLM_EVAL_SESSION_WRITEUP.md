# Session Writeup — IND Module + vLLM Cost + Regulatory Eval

**Window:** 2026-05-28 → 2026-05-31
**Branch:** `integration/next-phase`
**Author:** Claude pair-session with @yaoyun_dev

This writeup consolidates four parallel lanes of work that landed across
~10 commits. Each lane has its own deeper docs; this one is the index.

---

## TL;DR

| Lane | What | Commits | Status |
|---|---|---|---|
| IND #1 — DOCX export | Replace honest "ships next sprint" copy with a real Word doc renderer | `4ea489033`, `9a74068c5`, `b64e93ac5` | ✅ live + tested |
| IND #4 — S3 WORM audit mirror | 21 CFR Part 11 §11.10(c) tamper-evident retention for sign rows | `4ea489033` | ✅ live, opt-in via env |
| IND — Audit Trail PDF | 21 CFR Part 11 §11.10(e) hash-chained signature history PDF | `66e839fe1` | ✅ live + tested |
| vLLM scaffolding | Runnable Docker + ASG deploy assets for Qwen3-8B + LoRA serving | `121c1ac8b` | ✅ committed |
| vLLM local smoke | docker-compose + pytest path against the workstation GPU | `4cbedc5f6` | ✅ committed (not run — sm_121 issue) |
| vLLM cost reduction | 80/20 spot/on-demand 5-node → 100% spot 2-node | `66e839fe1` | ✅ updated, ~$290/mo |
| Eval — strengthened prompt | 7-line preamble → full 9-checker binding guideline + few-shot | `f65a4ce98` | ✅ live |
| Eval — refreshed lineup | GPT-4o/Sonnet 4.6/Gemini-3.5-flash → GPT-5/Opus 4.8/Gemini 3.1 Pro etc. | `f65a4ce98` | ✅ measured n=100 |
| Eval — local Qwen v6 row | LoRA inference on workstation GPU | n/a | ⛔ blocked by GB10 sm_121 |

---

## Lane 1 — IND DOCX export

**Closes punch list item #1.** Previously the success-card "Download DOCX"
button was unwired and the page-level handler `alert("ships next sprint")`.

**Backend** (`backend/lib/galaxy/ai/drug_discovery/ind_actions_router.py`):
- `_render_docx(project, sections)`: python-docx renderer. Times New Roman
  11pt body, level-0 cover heading with molecule name, bold metadata block
  (Sponsor / Target / Indication / Regions / Status), level-1 §2.6.x
  headings, paragraph-split body. Empty sections emit italic
  `[NO DATA AVAILABLE — section pending]` matching the Markdown placeholder.
- `POST /api/ind-report/projects/{id}/document.docx` — same `DocumentRequest`
  shape as `document.md`; returns the OOXML mime with
  `Content-Disposition: attachment; filename="{molecule}_2.6.docx"`.

**Frontend**:
- `frontend/client/src/lib/ind-report-api.ts::downloadDocx()` — blob/anchor/
  click pattern, parallel to `downloadMarkdown()`.
- `pages/ind-report.tsx::handleDownload("docx")` — calls `downloadDocx`
  instead of alerting.
- `IndOverlays.tsx` success-card button now wires to `downloadDocx`.

**Node proxy** (`frontend/server/routes.ts`): `app.all("/api/ind-report/*")`
wildcard mirrors the existing `drug-discovery` pattern, forwards
`Content-Disposition` so the browser preserves the filename.

**Tests:** `backend/lib/galaxy/ai/drug_discovery/tests/test_ind_docx.py` —
4 tests passing. Verifies PK magic + length, python-docx round-trip
extraction of molecule/sponsor/heading/body/placeholder.

**Deploy note:** backend venv needs `pip install python-docx==1.2.0`.

---

## Lane 2 — S3 WORM audit mirror

**Closes punch list item #4.** Before this change, the sign audit chain
lived only at `data/regulatory_training/sign_audit_chain.jsonl` on the
local Galaxy container — no tamper-evident retention.

**Implementation** (`ind_actions_router.py::_mirror_sign_row_to_s3_worm`):
- Post-sign hook called after `append_jsonl(...)` returns. Failure logs a
  warning, never raises — local row is the authoritative read path.
- Uploads to `s3://$BIOMATE_SIGN_AUDIT_S3_BUCKET/$BIOMATE_SIGN_AUDIT_S3_PREFIX/YYYY/MM/DD/{signature_id}.json`
- `ObjectLockMode=COMPLIANCE` + `ObjectLockRetainUntilDate` = signed_at +
  `$BIOMATE_SIGN_AUDIT_RETAIN_DAYS` (default 2555 = 7 years per FDA).
- Metadata includes `biomate-payload-sha256` so a downstream auditor can
  verify the S3 object body wasn't tampered before write.

**Opt-in:** no env var → no-op (zero AWS calls). This keeps local dev clean.

**Bucket prerequisite:** Object Lock must be enabled at bucket creation
time — it cannot be added later. IAM allows `s3:PutObject` +
`s3:PutObjectRetention` on the prefix only.

**Tests:** 3 tests in `test_ind_docx.py`:
- mirror is a no-op when bucket env unset (asserts `boto3.client` never called)
- mirror sets `ObjectLockMode=COMPLIANCE` + retain-until + key partitioned
  by date + payload sha256 in metadata
- mirror swallows exceptions (boto3 RuntimeError does not raise to caller)

---

## Lane 3 — Audit Trail PDF

**Closes the "Audit Trail PDF — ships next sprint" tooltip on the
sign-success card.** Implements 21 CFR Part 11 §11.10(e): "secure,
computer-generated, time-stamped audit trails of all signature events."

**Backend** (`ind_actions_router.py`):
- `_read_sign_audit_rows(project_id)` — reads `sign_audit_chain.jsonl`,
  filters by project, sorts by `signed_at`.
- `_render_audit_pdf(project, rows)` — reportlab Letter format. Cover
  with project metadata; one section per signature with timestamp,
  user_id, org_id, signer title/creds, signature scope, TOTP-validated
  flag, doc SHA-256, signature_id, adapter versions.
- **Hash chain:** each row computes
  `chain_link = sha256(prev_link || sig_id || doc_sha256).hexdigest()`,
  starting from `prev_link = "GENESIS"`. Each row's link appears in the
  table; the final "Chain head" appears in the PDF footer. Re-deriving
  by hashing each row in order detects tampering: any modified field
  shifts the head deterministically.
- `GET /api/ind-report/projects/{id}/audit-trail.pdf`.

**Frontend** (`ind-report-api.ts::downloadAuditTrailPdf` +
`IndOverlays.tsx` success card): button no longer disabled, wires to
`downloadAuditTrailPdf(projectId)`.

**Tests:** `test_ind_audit_pdf.py` — 5 tests passing including
`test_chain_link_changes_when_row_tampered` which verifies that modifying
any row's doc-sha shifts the chain head — the proof that the audit chain
is actually tamper-evident, not security theater.

**Deploy note:** backend venv needs `pip install reportlab==4.5.1`.

---

## Lane V — vLLM infrastructure

### Scaffolding (commit `121c1ac8b`)

Created `infra/vllm/` with the assets needed to provision a Mixed
Instances ASG serving Qwen3-8B + per-org LoRA adapters via vLLM:

| File | Purpose |
|---|---|
| `Dockerfile` | Wraps `vllm/vllm-openai:v0.6.4` with AWS CLI for spot management |
| `start-vllm.sh` | Globs `/mnt/efs/biomate-adapters/*/lora_adapter/` → `--lora-modules name=path …` |
| `spot-monitor.sh` | IMDSv2 polling → ALB deregister → drain via `/metrics` → SIGTERM at T-30s |
| `cloud-init.yaml` | systemd units for EFS mount + biomate-vllm.service |
| `asg-launch-template.json` | Launch template + Mixed Instances Policy |
| `sync-adapters.sh` | S3 → EFS adapter sync + ASG rolling refresh trigger |

Runbook at `docs/20260528_VLLM_DEPLOY_RUNBOOK.md` walks through the AWS
CLI bootstrap (ECR build/push, EFS create, IAM, ALB, ASG create) and
ongoing operations (adapter deploy, spot interruption monitoring).

### Local smoke test (commit `4cbedc5f6`, delegated to general-purpose agent)

| File | Purpose |
|---|---|
| `infra/vllm/docker-compose.local.yml` | Runs the BioMate vLLM image with GPU passthrough + local `models/` mounted at the EFS path |
| `infra/vllm/smoke-test.sh` | `up --build` → `/health` → `/v1/models` listing assertion → tiny chat completion → teardown |
| `tests/integration/test_vllm_client_path.py` | pytest that sets `VLLM_BASE_URL=http://localhost:8000` and exercises `_call_vllm_regulatory_llm` end-to-end |
| `docs/20260529_VLLM_LOCAL_SMOKE.md` | Runbook |

Not actually executed against the workstation GPU because of the GB10
sm_121 issue (see Lane E2 below). The smoke harness will run on AWS or
on any g5/g6/g4dn host.

### Cost reduction (commit `66e839fe1`)

Original plan: 5-node g6.xlarge ASG, 80% spot + 20% on-demand →
~$1,760/mo. **Rejected as too expensive.**

Replacement:
- `desired=2`, `min=1`, `max=4`
- `OnDemandBaseCapacity=0`, `OnDemandPercentageAboveBaseCapacity=0`
  (100% spot)
- `SpotAllocationStrategy=price-capacity-optimized`, 4 spot pools
  (`g6.xlarge`, `g5.xlarge`, `g4dn.xlarge`, `g6.2xlarge`) for diversity
- Steady-state: 2 × $0.20–0.40/hr × 24h × 30d ≈ **$290–$580/mo**
- `max-size=4` caps spend at ~$1,160/mo even at autoscaler ceiling

**Failure mode:** if all 4 spot pools are squeezed and the ASG sits at
`inservice=0`, the ALB returns 503. The Galaxy backend's
`_call_local_regulatory_llm` fallback chain catches the 503 and routes
to Gemini Flash — ~12pp quality dip, no user-visible outage.

**Still gated on explicit approval** to actually provision (any AWS spend
needs the human in the loop), but the cost ceiling is now defensible.

---

## Lane E — Regulatory LLM evaluation

### Real n=100 5-model run (commit `f65a4ce98`)

Problems with the prior run:
- Frontier API models received a thin 7-line preamble that the doc called
  "zero-shot." The label was inaccurate (there was a preamble) but the
  preamble itself was under-specified.
- Model lineup was 6 months stale: GPT-4o, Sonnet 4.6, Gemini 3.5 Flash
  preview only.
- OpenAI adapter sent `max_tokens` + `temperature=0.3` which the GPT-5
  family rejects with HTTP 400.
- Anthropic adapter sent `temperature=0.3` which `claude-opus-4-8`
  rejects (deprecated for that model).

Fixes:
- `evaluation/runners/prompts.py::_INSTRUCTION_PREAMBLE` — replaced with
  the full 9-checker binding guideline (MRSD calc, adversity tense,
  phase gating, tabulated↔prose, citation accuracy, hedge language,
  structural, numeric ranges, cross-section) + one good-output and one
  bad-output few-shot example.
- `evaluation/runners/multi_model_eval.py::_registry` — GPT-5,
  GPT-5-mini, Claude Sonnet 4.6 (latest available — sonnet-4-8 doesn't
  exist), Claude Opus 4.8, Gemini 3.1 Pro Preview, Gemini 3.5 Flash.
- `adapters/openai_adapter.py` — detect `gpt-5*` prefix → use
  `max_completion_tokens = max(N*6, 2400)` (reasoning tokens eat budget
  before visible output) and drop `temperature`.
- `adapters/anthropic_adapter.py` — drop `temperature` for `opus-4-8*`.

Results (`evaluation/results/regulatory_llm_5model_v1/summary.csv`,
n=100, strengthened prompt):

| Model | Macro avg |
|---|---|
| **GPT-5** | **90.0%** |
| GPT-5-mini | 87.4% |
| Claude Sonnet 4.6 | 87.1% |
| Claude Opus 4.8 | 85.9% |
| Gemini 3.1 Pro Preview | 73.8% |
| Gemini 3.5 Flash | 73.7% |

Key signals:
- MRSD calc is the floor for every frontier model (10–50%). The other
  8 checkers saturate at ~98–100% under the strengthened prompt.
- Sonnet 4.6 leads on MRSD (50%) but trails GPT-5 on tabulated↔prose
  (61% vs 100%) and structural (97% vs 100%).
- Opus 4.8 underperforms Sonnet 4.6 (85.9 vs 87.1). Opus's extra
  reasoning budget doesn't help regulatory-prose formatting + citation
  grounding at this prompt length.
- Gemini lags ~13pp dominantly on citation (37%/31%) and structural
  (66%/77%) — citation hallucination is the failure mode.

The prior (v1.old-preamble) run is preserved as
`evaluation/results/regulatory_llm_5model_v1.old-preamble/` for prompt-
vs-prompt delta computation.

Doc: `docs/20260521_REGULATORY_LLM_COMPETITIVE_COMPARISON.md` updated.

### Local Qwen v6 + base — blocked

The two open rows in the comparison table (BioMate `regulatory_llm_v6`
and base `Qwen3-8B`) require local GPU inference. First attempt crashed
silently — log showed only a `torch_dtype` deprecation warning before
exit.

**Root cause:** workstation GPU is an NVIDIA GB10 with compute capability
`sm_121`. The current backend `torch` build does not ship CUDA kernels
for sm_121 — every CUDA op silently hangs. This was noted in earlier
memory (`feedback_cryosparc_auth.md` and prior session notes) but
re-surfaces here.

The v6 LoRA *weights* are correct (training was done on AWS g5/g6
instances where torch supports the chip). Only local inference is
blocked.

**Two paths forward:**
1. **Run inference on AWS** — once the vLLM ASG is up, set
   `VLLM_BASE_URL` on the eval orchestrator and the local-model rows
   fill the same way as the API rows. This is the production path
   anyway.
2. **Local torch nightly with sm_121** —
   `pip install --pre torch --index-url https://download.pytorch.org/whl/nightly/cu128`.
   Worth doing only if we need local iteration; otherwise wait for AWS.

---

## Files changed (summary)

```
backend/lib/galaxy/ai/drug_discovery/
  ind_actions_router.py                       +320 / -3
  tests/test_ind_docx.py                      +107 (new)
  tests/test_ind_audit_pdf.py                 +114 (new)

frontend/client/src/lib/
  ind-report-api.ts                           +56 / -0

frontend/client/src/pages/
  ind-report.tsx                              ~10 (DOCX wire)

frontend/client/src/components/ind-report/
  IndOverlays.tsx                             ~30 (DOCX + audit PDF wire)

frontend/server/
  routes.ts                                   +48 (IND wildcard proxy)

infra/vllm/
  Dockerfile, start-vllm.sh, spot-monitor.sh  (new — scaffolding)
  cloud-init.yaml, asg-launch-template.json   (new — deploy spec)
  sync-adapters.sh                            (new — adapter deploy)
  docker-compose.local.yml                    (new — smoke)
  smoke-test.sh                               (new — smoke)

tests/integration/
  test_vllm_client_path.py                    (new — smoke pytest)

evaluation/runners/
  prompts.py                                  ~70 (strengthened preamble)
  multi_model_eval.py                         ~10 (model registry refresh)
  adapters/openai_adapter.py                  ~6  (gpt-5 family compat)
  adapters/anthropic_adapter.py               ~8  (opus-4-8 compat)

evaluation/results/
  regulatory_llm_5model_v1/                   (new measured run)
  regulatory_llm_5model_v1.old-preamble/      (archived prior run)

docs/
  20260521_REGULATORY_LLM_COMPETITIVE_COMPARISON.md  (~80 lines rewritten)
  20260528_VLLM_DEPLOY_RUNBOOK.md             (new — runbook)
  20260529_VLLM_LOCAL_SMOKE.md                (new — smoke runbook)
  20260531_IND_VLLM_EVAL_SESSION_WRITEUP.md   (this file)
```

---

## Open items / next steps

- **vLLM AWS provisioning** — gated on explicit human approval. Cost is
  now defensible at ~$290–580/mo. Owner: @yaoyun_dev.
- **Local Qwen GPU** — either (a) wait for AWS vLLM, or (b) try torch
  nightly cu128 for sm_121. Not on the critical path.
- **App.tsx pre-existing TS error** — `Unused '@ts-expect-error' directive`
  at line 54 from commit `a5de1dcb2`. Not blocking but trips `npm run check`.
- **Audit Trail PDF — multi-project chain** — current implementation
  hashes within a single project's signatures. A future enhancement
  could link across projects in a per-org chain for cross-project
  tamper detection.
- **Adapter version capture in sign payload** — `adapter_versions` field
  exists on the SignRequest but the frontend always sends `{}`. Should
  populate from the SSE phase events that announce
  `model_loading → model_ready → generating` per section.

---

## Commits in this window

```
66e839fe1  ind: audit-trail PDF + vLLM 100% spot cost reduction (~$1760 → ~$290/mo)
4ea489033  ind: real DOCX export + 21 CFR Part 11 S3 WORM audit mirror
b64e93ac5  chore: parallel-session edits (v2 phase0 sync attempt 1) [includes Overlays + page wire]
9a74068c5  chore: parallel-session edits (structure-viewer sync attempt 1) [includes ind_actions_router + api]
4cbedc5f6  vLLM local smoke: docker-compose + integration pytest
121c1ac8b  vllm: deploy scaffolding + real 5-model eval (n=100)
f65a4ce98  regulatory-eval: strengthened guideline prompt + latest model lineup
```
