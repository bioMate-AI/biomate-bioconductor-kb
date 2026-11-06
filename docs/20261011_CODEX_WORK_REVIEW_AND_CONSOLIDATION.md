# Codex harness work — review + consolidation before integration

**Date:** 2026-10-11
**Input:** the codex session's harness/eval/training work (roadmap `20261009_INTEGRATED_HARNESS_AND_MODEL_ROADMAP.md`
+ uncommitted working-tree changes + `evaluation/local_trial/{harness_reuse,real_comparison}/`).
**Method:** two independent read-only reviews (code-correctness/regressions; diagnosis/eval/training/coherence),
each citing file:line, plus a firsthand read of the roadmap implementation record. Nothing was edited or integrated.

## 1. Solidity verdict — codex's work is SOLID
- **Code-correctness / regressions:** SAFE to integrate as-is. Frontend vitest **43/43**, backend
  `pytest test_chain_dag_api.py` **5/5** (py3.9), `tsc --noEmit` clean. Legacy step-approval and
  single-workflow routing are **untouched**; edge cases (branch reorder, ambiguous key, parent-only
  transition, render-loop referential equality, stop-polling on terminal/partial) are tested with
  **non-vacuous** assertions. The highest-risk backend change (`workflow_chain.py:1350` step_key) is a
  strict 1:1 map — no IndexError/AttributeError; step_key is a display/manifest label only.
- **Diagnoses (both verified true, firsthand):**
  1. *Routing/generation conflation* — `galaxy-assistant.ts:4371-4379` flips `needsWorkflowGeneration=false`
     whenever `execution-intent-guard.ts` matches "do not launch" (regex `:11` also matches "generate/create").
     The CLL request ("…do not launch jobs yet … return an executable plan") tripped it →
     `chat_only/research_question/workflow=null` (`planning_review.json`). Real.
  2. *Result-collection false-negative* — `benchmark-orchestrator.ts:224-227` reported "no method produced
     clusters" because the collector called the protected output endpoint **without the session**; clusters
     existed in S3 (`authenticated_output_api.json`). Real.
- **Fixes are root-cause + CLAUDE.md-compliant:** credential forwarded through (`routes.ts:12868-12878`),
  `getRun` reads storage directly instead of a self-GET that failed auth — "fix the credential architecture,
  don't hard-code a fallback." Scorer fix sound (shared cohort / null-for-insufficient / no arbitrary ties /
  partial-coverage all hold).
- **Training plan:** methodologically disciplined (dev-case contamination of the 3 worked examples is
  explicitly handled; failure-cause labels separate software defects from model mistakes; split-before-augment;
  paired base-vs-adapted on the same harness; SFT only after frozen contracts + measured residual gaps). The
  only real risk is **data substrate**, not methodology (see §5 R1–R4).
- **codex is honest about scope:** component tests ≠ end-to-end acceptance; live execution unverified (local
  ports were down); the live model was hosted `gpt-5.6-luna`, not Spark-27B or a trained checkpoint; no
  committed real scientific score (`verified_scores.json` absent); UI draft-without-launch + whole-plan recovery
  still pending.

## 2. The coherent architecture — LAYER the parallelism, don't let it proliferate
The single most important consolidation finding: there are now **four "parallel" surfaces** — `pattern_router`
(decision), `workflow_chain.py` DAG (durable Batch fan-out/join), `benchmark-orchestrator.ts` (benchmark fan-out),
and `map_reduce.py` (in-process fan-out). They must be **layered**, not peers:
```
 1. INTENT/DRAFT CONTRACT   requested-artifact {explanation|draft_plan|results} × action {read|plan|execute}
                            (codex's guard fix = the FRONTEND half; must be SHARED with the backend)
 2. PLAN DECISION           pattern_router — single vs multi / pipeline / parallel-fanout (capability-gated)
 3. ONE DURABLE SUBSTRATE   workflow_chain.py DAG (depends_on / max_parallel / join, durable, Batch).
                            Generalize benchmark-orchestrator INTO this; do not leave a 3rd durable surface.
 4. IN-PROCESS map_reduce   ONLY for in-process sub-steps (analysis/agent fan-out) layered within #3 — not a peer.
 5. GROUNDED EVIDENCE       corpus_fs — the parent evidence/report contract reads from it (not a new store).
```
**Three distinct plan-discards — never conflate (one per layer):**
- (i) frontend `galaxy-assistant.ts:4371` guard discard — **codex is fixing** this.
- (ii) backend `ai_assistant.py:724-728` TaskDecomposer-graph → single-task discard — belongs to the P0
  logical→executable adapter + `pattern_router` wiring, **NOT** the guard.
- (iii) `processMultiIntent` path-dedup discard — codex's multi-intent fix.

**No file-level collision:** the built components (`map_reduce`/`pattern_router`/`corpus_fs`, on
`feat/orch-retrieval-s2-20261008`) are absent from this branch and `next-phase`; codex's edits are in different
files/layers. Complementary, not conflicting.

## 3. Integration readiness
- **SAFE to integrate now** (both reviews green): the benchmark **scorer** + **credential/getRun** fixes, the
  **execution-intent-guard** (as a point-fix), and the **chain whole-plan / partial / blocked / stop-polling** work.
- **Reconcile BEFORE building** the P0 logical→executable adapter / P1 durable fan-out (§4) — to avoid a divergent
  fan-out and a half-wired draft/launch contract.
- **NOT end-to-end ready** (codex concurs): chat still cannot emit a draft-plan-without-launch; in the live
  ADMET/PBPK path "generate" ≈ one-click launch, so draft/launch separation needs a submission-time gate, not a
  guard-only edit; UI whole-plan recovery pending; no committed real scientific score; the untouched eval set and
  validated-real training episodes do not exist yet.

## 4. Reconciliation order (settle before building the adapter)
1. **Shared draft/approval/launch contract.** The frontend guard must not kill *generation* when the user asks
   for a draft without launch; the same {artifact × action} contract must flow to the backend so `pattern_router`
   can still PRODUCE a multi-plan draft. (codex PART-1a × `pattern_router` hook.) Needs a submission-time
   "generate-card-but-don't-auto-execute" gate, since one-click generate ≈ launch today.
2. **Pick ONE canonical durable fan-out/join substrate** — `workflow_chain.py` DAG — and route
   `pattern_router`'s PARALLEL_FANOUT into it; **generalize** the benchmark-orchestrator's hard-coded 6-method
   registry into it rather than leaving a third surface. Reuse `map_reduce` only for in-process sub-steps.
3. **Wire the `ai_assistant.py:724` TaskDecomposer discard** through the P0 adapter + `pattern_router` — distinct
   from the guard discard codex fixed.
4. **Decide the merge of `feat/orch-retrieval-s2-20261008` into `next-phase`** before building the P0 adapter, so
   it imports `map_reduce`/`pattern_router`/`corpus_fs` instead of reimplementing (reconciliation doc option (a)).
5. **Point the parent-evidence/report contract at `corpus_fs`**, and have the P1 report renderer **surface failed
   methods as explicit rows** (the scorer currently exposes them only via `coverage.missing_methods`).

## 5. Open risks + confirmations
- **Training data substrate (R1–R4):** an *untouched* eval set and *validated-real* training episodes don't exist
  yet (the 3 worked examples are dev/regression cases; Spark-27B fixtures are synthetic with fixture-supplied IDs;
  the one real run is a negative/dev example on a hosted model). SFT cannot legitimately start until C0/C1 measure
  residual gaps on the actual local checkpoint. The plan sequences this correctly; it is prerequisite "First" work.
- **Confirm intended** (flagged by the code review, out of scope but in the same working tree):
  `nextflow-workflow-viewer.tsx` removes the output-location picker so project-scoped runs now **always** write to
  the project folder (previously opt-in) — labeled "hidden at user request." Confirm this behavior change is wanted.
- **Minors (non-blocking):** `isActiveJob` and `pollChainStatus` have no production callers (inert/dead code);
  the `blocked`/`submitting` badges lack `dark:` variants (minor visual). No action required for safety.

## 6. Bottom line
codex's work is solid, honest, and complementary to the built orchestration/retrieval components. The **point-fixes
are safe to integrate now**; the **adapter/fan-out build must follow the §4 reconciliations** so the system has one
layered parallel path (decision → one durable substrate → in-process map_reduce) and one shared draft/launch
contract — not four peer surfaces and three uncoordinated plan-discards.
