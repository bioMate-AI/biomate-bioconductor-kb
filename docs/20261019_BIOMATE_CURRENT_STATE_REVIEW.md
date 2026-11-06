# BioMate — Grounded Current-State Review

**Date:** 2026-10-19
**Purpose:** an honest, code-verified review of what BioMate actually is and does today — **before** any improvement is designed. No proposals in this document.
**Method:** three independent code/DB/docs reviews (live AI-assistant flow; workflow-execution engine + QC loop; eval results + live/dormant map), verified against HEAD, not assumptions.

---

## 1. Architecture reality (what the live system actually is)

- **The live chat path is the Node/TypeScript pipeline** (`frontend/server/galaxy-assistant.ts`, ~10k lines), driven from `routes.ts` `POST /api/chat/stream`. The Python `ai_assistant.py` / `pattern_router.py` / `agent_orchestrator.py` are **not imported by the Node server** — they are reached only through three narrow HTTP endpoints (`/api/ai_assistant/generate_workflow`, `/research_query`, `/api/literature/search`). The sophisticated Python orchestration is **dormant**.
- **Default LLM backbone is Gemini 3.8 Flash** (intent + response), with a real fallback chain **Gemini → Claude → OpenAI → Ollama**. Claude is the fallback and the reliable tool-loop backbone; Gemini Pro routing is coded but hard-disabled ("Pro hangs 110s+").
- **Execution engine is real and production-wired:** `POST /api/nextflow/execute` → local `subprocess.Popen` Nextflow head → **AWS Batch** task dispatch (`NEXTFLOW_USE_AWS=true` in `start_backend.sh` + deploy compose), S3 I/O, status endpoint, completion handling. Cross-worker run-state via a Redis store (opt-in; **silently falls back to in-process InMemory** if `REDIS_URL` is unset/unreachable — then the cross-worker fix is inactive).
- **Deployment:** `dev-public.biomate.ai` is the **single live environment and doubles as prod** (no separate prod app tier). Manual `sync_to_dev.sh` rsync, **no CD**. The only always-on "production" component is the AWS billing/Lambda stack.

## 2. What genuinely works (the real core)

1. **Routing over the curated catalog — the one clear, defensible win.** Same-item routing = **0.965** (n=200) vs raw LLMs 0.35–0.62; the "catalog dividend" lifts *any* model **+34–64pp** (the own 9B base goes 0.18→0.82 when handed the catalog). This is BioMate's actual moat.
2. **Workflow execution on AWS Batch** — real end-to-end; **24/24 drug-dev workflows validated on Batch** (per `docs/20260418_...`). Drug-discovery `.nf` are real RDKit/Vina/etc. container processes, not stubs.
3. **Tool-level dense/embedding search** — real and populated (12,299/12,312 vectors in `tools.embedding`). **Workflow search, by contrast, runs FTS/BM25-only** (the dense `.npz` is absent and `workflow_embeddings` is empty; even when live it's only a ±0.5 tiebreaker).
4. **ADMET prediction model** — AUROC 0.91–0.93 on TDC splits, beating published baselines.
5. **Agentic tools are wired and executable** on both backbones — `run_code` really runs Python/R/bash in a hardened Docker sandbox; `search_literature` really hits the federated backend. (The "dead on Gemini" bug was fixed in `b79141bb9`.)
6. **IND report assembly** (Python CTD §2.6.x builder + optional Gemini narrative, fails open).
7. Memory injection (LTM/episodes/corrections/cross-session), skills, dataset context, and QC/findings for the common ADMET/CryoEM/preproc paths.

## 3. Half-built / in-flux (2026-10-19 active work)

- **Run-history persistence:** outputs persist, but **QC-events do not** (designed, not implemented — it touches the crash-sensitive Galaxy monitor); findings persistence just got a fix. Root cause of a real stuck run traced to an S3 path/region bug + orphaned Batch completions + all-pass runs recording no gate rows.
- **Step View** — implemented but **not conformance-tested** (no spec-08 edge-case pass).
- **ADMET endpoint coverage beyond AMES** — diagnosed (CYP/bioavailability not promoted; dead `herg_inhibition_prob` key; a container/runtime failure), **not fixed** (edits executed Nextflow code, can't E2E-verify until the container issue clears).
- **Gemini tool-calling reliability** — tools attach + execute, but the code *itself* still flags residual uncertainty about whether Gemini reliably *chooses* to call them (a `__DIAGTOOLS__` sentinel "the last unknown").
- **MCP multi-workflow param-prefill** — just fixed (workflow #2 in a parallel set wasn't re-prefilled).

## 4. Dormant / off / aspirational

- **Multi-agent orchestrator** — built but **inert, zero live callers**, flag-default-off (`BIOMATE_PATTERN_ROUTER_ENABLED`). Live routing is an LLM classifier + `inferActionsFromType` + a large **hand-written regex-override block** in TypeScript.
- **Closed-loop QC auto-loop** — **advisory only in production**: on a QC "halt" the run is **not** killed or auto-restarted; it emits SSE gate results + stores remediation suggestions for the user to manually relaunch. The real retry→escalate loop exists only in the per-domain orchestrators, exercised by **simulation/benchmark** harnesses.
- **Billing UI** (commented out — page crashes), **CRO Library** (route + nav disabled), **IND Report** (live by URL, hidden from nav).
- **On-prem 9B LLM as a frontier competitor** — SFT/DPO gave **no win** (v3 SFT loses to production `sft_gold`; param_prefill regressed); GRPO is a held, self-described **LOW-EV** bet.
- **Workflow-level dense retrieval** — code complete, not loaded (see §2.3).

## 5. Eval reality (honest, from the RealBio same-item harness)

| Capability | Target | Actual | Status |
|---|---|---|---|
| **routing** | ≥80% | **0.965** (same-item) / 94.6% | **PASS — the strong win** |
| **ADMET** (model AUROC) | ≥70% | 0.91–0.93 | **PASS** (model quality; not same-item harness) |
| **pbpk** | ≥60% | **0.20** (3/15 within-2-fold) | **FAIL** (ties best LLM, still far below target) |
| **biomni_eval1** | ≥65% | **22%** | **FAIL** |
| **param_prefill** | ≥70% | withdrawn (non-same-item; rerun pending) | not currently passing as same-item |
| **boin** | ≥70% | withdrawn; same-item rerun **infra-blocked** (dead dev AWS key) | pending |
| **stability** | ≥90% | mean_score **0.0** (consistent, but consistently zero) | non-measurement |

The team's own posture: several once-headline numbers (param_prefill 0.848, boin 0.80, protocol-QC 0.925, pbpk 100%) were **withdrawn** as cross-harness. Leaderboard headline: *"no single system dominates every task."*

## 6. Grounding reality (relevant to recent search/Grounded work)

- **Citation grounding is NOT automatic in normal chat.** It fires only for research-type intents (Python `research_query`) or if the model *elects* to call `search_literature`. A plain conversational turn — or any turn where a runnable workflow card was generated, or the messaging-connector/OpenRouter paths — has **no live citation grounding**, and there is **no "how this was searched" provenance surface** in the live path.
- The federated literature path now includes Crossref (4 sources), but the structural search limits (KBs siloed from the citation path, flat merge, no clinical/web/regulatory) remain as previously audited.

## 7. Cross-cutting honest themes

1. **The moat is retrieval/routing over the curated, execution-validated catalog** — not the model, not autonomy. The catalog dividend is the real, measured edge.
2. **The live system is simpler than the codebase implies** — a TS pipeline over Gemini Flash + three Python endpoints; most of the advanced Python (orchestrator, pattern router) is dormant.
3. **Advisory, not autonomous** — the QC loop, citation grounding, and remediation are all **advisory/elective**, not closed-loop/automatic. The "autonomy" is largely aspirational.
4. **Catalog validation is partial** — of 4,210 workflows, ~**696** carry observed-clean real-exec evidence; ~1,093 have recorded failures; **1,866 were never run**. Drug-discovery's best validation lives in `docs/` (Batch 24/24), not in the DB's `real_exec_status`.
5. **Honest benchmark posture, narrow real wins** — routing and the ADMET model clearly pass; pbpk and biomni clearly fail; the rest are withdrawn/pending/non-measurements.
6. **Single-env, manual-deploy, infra-fragile** — one dev box = prod, manual sync, a dead AWS key currently blocking benchmark reruns and orphaning some Batch completions.

---

**No improvement proposals are made here, by design.** This review is the factual baseline any improvement design should start from.
