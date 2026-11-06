# Local LLM coding ability (Nextflow convert/fix/write + run_code) — assessment & improvement plan

**Date:** 2026-10-05. Honest assessment grounded in committed numbers; no capability asserted without a
cited measurement. Companion to the task-split (`docs/20260912_onprem_llm/20261001_LLM_HARNESS_TASK_SPLIT.md`).

## 1. Assessment — coding is the local LLM's weakest class (by design of the task-split)
Routing/selection/param are **harness-carried** (retrieval does the work; the 9B matches frontier with the
catalog). Coding is the opposite: **open-ended generation, no retrieval answer → LLM-bound**, the one place
a 9B is genuinely behind frontier. Measured (base 9B → after SFT):

| task | base | SFT | note |
|---|---:|---:|---|
| `autofix_repair` (fix a broken workflow) | 0.190 | 0.402 | partial gain |
| `workflow_generation` (wire steps, correct I/O) | 0.214 | 0.280 | hard |
| `out_of_catalog_composition` (compose when nothing fits) | 0.124 | 0.099 | hardest — **SFT HURT** |
| `findings_interpretation` | — | 0.286 | LLM-bound |

- RealBio's `autofix 0.87` / `workflow_gen 0.50` are the **catalog-assisted / coarse-metric** versions —
  `workflow_gen` is 0.50 for *every* model incl. frontier, so it does **not** discriminate coding skill.
  The table above is the real signal.
- **The concept-CPT running on spark does NOT address coding** — it lifts knowledge recall, not code
  generation. Coding is a separate lever.

## 2. Why it's still tractable without a frontier model — code has a cheap verifier
"Does the Nextflow run? does the output meet the contract?" is checkable → a weak one-shot generator
becomes usable inside a verify-fix loop:
- **Convert existing work → Nextflow** = *adaptation* (retrieve a similar validated workflow from the
  catalog / 283-wf subworkflow set / nf-core modules, then modify). Retrieval-seeded → more tractable for
  the 9B than blank-page generation.
- **Fix / write Nextflow:** the pipeline is the verifier → generate→run→read-error→fix (pass@k) lifts
  reliability far above one-shot 0.2–0.4. This is what the autofix/QC auto-loop already embodies; the 9B is
  the cheap first-draft author, not the oracle.
- **`run_code` ad-hoc box (Python/R/…):** execution = verifier; write→run→fix works. Box exists
  (`docs/20260518_RUN_CODE_SANDBOX_PRODUCTION_PATH.md`, `docs/20260819_SANDBOX_MODE_COMPLETE.md`).
  Caveat: a known plumbing bug where the model sometimes doesn't **invoke** run_code in live chat
  (classification/prompt issue, NOT a model limit) — fix separately (`project_agentic_tools_gemini`).
- **Out-of-catalog:** the 9B should **escalate/abstain**, not hallucinate a pipeline — route to a stronger
  model or a human by design.

## 3. The gap: no execution-graded coding benchmark exists
RealBio's `workflow_gen 0.50` is non-discriminating and nothing measures convert/fix/write by **execution**.
Without that, coding ability can't be measured or improved honestly. **Prerequisite = build it** (§4.1).

## 4. Both skills AND LLM training — division of labor (they multiply)
Coding needs **both**, and each does what the other can't:
- **Skills (harness-side)** = packaged procedures over the catalog + sandbox + execution grader: a
  *convert-to-nextflow* skill (retrieve a similar validated workflow → adapt → stub-run → fix), a
  *fix-nextflow* skill (parse error → targeted repair loop), a *write-process* DSL2 template-filler, a
  *run_code* write→execute→read→fix loop, and an *escalate/abstain* policy for out-of-catalog. Skills turn
  a modest generator into a production-reliable one via pass@k over a verifier (reliability ≈ 1−(1−p)^k).
- **LLM training (code SFT/RL)** raises the **floor p** — the irreducible first-draft correctness and the
  *repair competence* (ability to turn an error message into a correct fix). Skills amplify p but cannot
  manufacture it: a verify-fix loop wrapped around a ~0 generator on out-of-catalog still converges to ~0.
- **The key ordering insight:** skills + the execution verifier are the **data engine** for the training.
  The autofix/QC loop *is* a verifiable-rewards environment (`project_enterprise_agent_modernization`): every
  stub-run/real-run that passes, and every successful error→fix, is a verified trajectory. So build the
  skills+verifier **first** — they generate the execution-graded code-SFT/RL data (reject-sampling on "it
  ran"), which trains a better floor, which makes the skills converge faster. Skills ⇄ training is a loop,
  not two parallel tracks. The benchmark in §4.1 is both the yardstick and the grader that mints the data.

## 4′. Improvement plan (ordered)
1. **Build an execution-graded Nextflow coding benchmark** (`evaluation/datasets/nextflow_coding/`) —
   convert / fix / write tasks scored by a tiered **execution** grader: (A) `nextflow` config/parse, (B)
   `-stub-run` (validates the whole DAG + channel I/O wiring with NO real tools/data — the cheap "does it
   run as a pipeline" signal), (C) a few real tiny runs with an output-content contract. Ties to
   `project_execution_grader`. *(being built now.)*
2. **Baseline** frontier (OpenRouter) + the local 9B (once it is served for inference — it is training now,
   not served) to size the gap and confirm the benchmark discriminates.
3. **Execution-grounded code SFT** — reject-sampling: keep only generations that PASS the tier-A/B grader as
   training pairs (self-distillation on verified code). This, not concept-CPT, is the coding lever.
4. **Verify-fix harness loop + retrieval-seeded adaptation + escalate/abstain** — ship the generate→stub-run
   →fix loop around the 9B; seed from retrieved validated workflows; abstain on out-of-catalog.
5. **Fix the run_code invocation plumbing** so the model actually calls the sandbox in live chat.

## 5. Honesty flags
- Local 9B is **not currently served** → coding eval against it waits until after the spark CPT finishes and
  a vLLM endpoint is up. Frontier baselining can proceed now.
- The §1 SFT numbers are from the task-split eval set, not a Nextflow-execution benchmark (which doesn't yet
  exist — that's exactly §4.1).
- Coding ability will NOT be moved by the concept-CPT; do not attribute any coding gain to it.
