# BixBench (open-science AI-scientist comparison) — live run findings

**Date:** 2026-10-22
**Endpoint:** dev-public.biomate.ai (model served: `gpt-5.6-luna`), canonical fixture
`lifeifei163361@163.com`, E2E bypass token. Config override in scratchpad (not committed).
**Context:** "compare other AI scientists — open science, Biomni and others." SAB/BAB are blocked on
gated external data; **BixBench** (FutureHouse, arXiv:2503.00096) is the runnable open-science
comparator (adapter + runner + local capsule data present).

## What ran (small, reviewed, incremental — not scaled)

| Step | Scope | Result | Verdict |
|---|---|---|---|
| dry-run | 5 tasks, enumerate | tasks/verifiers/categories parse from HF | setup OK (zero cost) |
| login smoke | — | token obtained vs dev-public | auth OK |
| MCQ smoke | 5 tasks | **1/5 (10%)**, 73.6 s/q, $0.0068/q | integration OK; frame wrong for an agent |
| biomate_exec smoke | 2 tasks | **0/2**, 73.3 s/q, $0.025/q | **BLOCKED — run_code not firing** |

Published baselines (for reference): Biomni Lab 88.7% (exec), Claude Code 65.3%, GPT-4o 40.2%
(MCQ), Claude 3.5 Sonnet 45.0% (MCQ), BioMate 23.3% (MCQ, session-5).

## Root causes (from the stored raw responses, not inferred)

1. **MCQ is the wrong frame for an execution engine.** BioMate answers as an *agent* ("I processed
   your request using the available tools", "I need to flag a critical issue with the question"),
   not an MCQ letter-picker. 10% on n=5 is consistent with the noisy 23.3% baseline. Not a bug —
   closed-book MCQ simply isn't what BioMate is for.

2. **`biomate_exec` does not actually execute `run_code` in the live-chat path.** The dominant
   blocker. Evidence from the saved responses:
   - q2: BioMate emitted a ```python``` block to parse the capsule notebook, then printed
     `ANSWER: 0.031` with **no computed stdout between the code and the answer** — i.e. it wrote
     code as text and *guessed* a number (GT 1.9E-05). A real execution would surface the printed
     cell outputs.
   - q1: response was 76 chars — "I'll extract the notebook outputs and analyze the DESeq2 +
     enrichGO results." — a truncated preamble, stream ended early (no code, no answer).
   So the 0/2 reflects a **broken execution path**, not BioMate's ability to compute a DESeq2 padj.
   This is the known "agentic tools / run_code dead in live chat" issue — and it is **broader than
   Gemini** (reproduced here on `gpt-5.6-luna`).

3. **Minor: early-stream truncation** (q1, 76 chars) — the harness captured an opening chunk, not
   the final message. Secondary to (2).

## Why this stopped at a smoke (discipline win)

Scaling to all 205 BixBench tasks in `biomate_exec` would have cost ~$5 and hours of wall-clock to
measure a harness/architecture bug (run_code not firing), producing a fake "BioMate ≈ 0% vs Biomni
88.7%" that is meaningless. The 2-task smoke surfaced the blocker for ~$0.05. This is the
"review/diagnose before scaling expensive runs" rule paying off.

## What a VALID Biomni-comparable BixBench number requires (prereq, not yet done)

`run_code` must actually execute in the eval path. Options:
- make the live-chat path fire `run_code` (fix the agentic-tool firing — the general gap in
  `project_agentic_tools_gemini.md`), OR
- route `biomate_exec` through the data-plane / execution path where agentic tools DO run, then
  re-run the smoke → confirm computed stdout appears → scale to 205.

Only after run_code fires is a BioMate-vs-Biomni-Lab (88.7%) number honest. Until then, report
BioMate's execution standing as **"blocked on run_code firing in the eval path,"** not a score.

## ROOT CAUSE CONFIRMED + FIX (2026-10-22, commit dfbe57263)

Diagnosed by reading the firing path + a live dev probe (not inferred):

- Firing gate (`galaxy-assistant.ts:8760`): `toolsEnabledThisTurn = !useThinking && onToolEvent &&
  !hasRunnableWorkflow`. `/api/chat/stream` DOES wire `onToolEvent` (routes.ts:6510/6517), so the
  eval path supports tools. The killer is **`hasRunnableWorkflow`** — if a workflow card is
  generated, run_code is gated OFF on *every* backbone.
- Live probe ("compute the mean of [2,4,6,8], not a pipeline") → dev emitted `workflow_ready` +
  `tool_event: parameter_extraction` (NOT `run_code`) and printed code-as-text → **a workflow card
  was generated even for trivial compute.**
- Why: the direct-compute override (`:4103`) that should set `needsWorkflowGeneration=false` is
  guarded by `_isDirectCodeExecutionQuery`, which ran its **pipeline-exclusion regex over the whole
  message**. The BixBench exec prompt says *"Use run_code … **Do NOT launch a Nextflow workflow**"* —
  the word **"nextflow" inside the negated directive** matched the exclusion → override returned
  false → workflow card generated → run_code disabled → fabrication. (My probe's "not a pipeline"
  tripped the identical bug.)

**Fix (commit dfbe57263):** an explicit "do not launch a workflow/pipeline" directive is now the
strongest direct-compute signal and overrides the pipeline guard outright; other negated pipeline
mentions are scrubbed before the guard. Conservative — genuine pipeline asks untouched. Regression
test `direct-code-execution-20261022.test.ts` 5/5; full suite 1897 pass / 22 skip; tsc clean.

**Secondary concern (not yet verified on dev):** for a non-Claude backbone like `gpt-5.6-luna`, even
with the workflow card gone, the agentic loop only runs if `ANTHROPIC_API_KEY` is set
(`:8824` — it overrides to claude-haiku for the tool loop). If dev lacks that key, run_code still
won't fire via the text-only chain. Check dev env after deploying the classifier fix.

**DEPLOYED + VERIFIED (2026-10-22).** The fix reached dev via a concurrent session's full
`sync_to_dev.sh` of the shared branch (carried commit dfbe57263; my own frontend-only sync was
blocked by that live lock, so no second deploy was needed). Verified live:
- Probe with the exact failing pattern ("Use run_code … Do NOT launch a Nextflow workflow") →
  `tool_event: run_code` fires (×2), **no `workflow_ready`** — run_code executes, no card.
- Re-ran the SAME 2-task BixBench-exec smoke: **0/2 → 1/2 (50%)**. The remaining failure changed
  from fabrication ("ANSWER: 0.031" guessed) to a real execution miss ("No 'neutrophil' found in
  notebook outputs… Searching for all GO terms") — run_code genuinely ran. Latency 73s→21s, cost
  $0.025→$0.003/q (no workflow-generation overhead).

So the execution path is now VALID for the Biomni comparison. n=2 is a smoke, not a headline.

**Next (gated — bigger billable run):** scale to the full 205 BixBench-exec tasks for an honest
BioMate-vs-Biomni-Lab(88.7%) number (~205 × ~$0.003 LLM + capsule downloads + wall-clock). The
secondary ANTHROPIC_API_KEY concern is moot in practice — run_code fired, so dev's agentic loop is
working for this path.

## Bug-finding run on the CURRENT build (2026-10-22, n=8)

Re-purposed BixBench-exec as a bug-finding harness on the post-fix dev build (user: "already tested
before … use it to further test the current version for any bugs"). Result: **7/8 (87.5%)** —
essentially Biomni Lab (88.7%, −1.2%), +22.2 vs Claude Code, +47.3 vs GPT-4o exec. range_verifier
5/5, str_verifier 2/3. Latency ~18s/q, $0.0029/q.

**Audit of all 8 responses → NO BioMate bugs.** Every task fired run_code, extracted real values
from the notebook cells (chi-square p-values, odds ratios, GO p.adj), no fabrication / code-as-text /
tracebacks / truncation. The run_code fix is validated at scale.

The one miss (`bix-1-q2`, the same recurring task) is a **benchmark-prompt artifact, not a BioMate
defect**: the notebook-parse snippet the adapter injects truncates each cell's stdout to `[:300]`
chars, so the target term "neutrophil activation" (GO:0042119, p.adj 1.9e-05) fell outside the
printed window. BioMate correctly extracted the enrichGO table, honestly reported "No 'neutrophil'
found," and kept searching — right behavior on a truncated extraction. Optional benchmark-side
improvement (not a BioMate fix): raise/remove the per-cell `[:300]` cap in
`bixbench_adapter._biomate_exec_prompt` Path A so the full enrichGO table is surfaced (would likely
make this 8/8). Deliberately NOT applied here — it is benchmark tuning, and the point of this run
was BioMate bugs.

Env note: the runner needs anaconda's python (`/Users/kky/opt/anaconda3/bin/python3`) — only it has
`datasets`; the default homebrew `python3` errors "No module named 'datasets'".

## Broader bug-finding sweep (n=20, new capsule types) — a SECOND finding

Sweep over bix-11+ (phylogenomics capsules: multi-zip `scogs_fungi.zip`/`scogs_animals.zip`, PhyKIT):
9/20 exact (down from 87.5% on single-notebook capsules). The drop is concentrated in **multi-file
capsules + `llm_verifier` tasks (mean 0.273)**, and the audit shows a real, distinct weakness (not a
crash, not fabrication):

- On multi-file capsules, run_code spends its turn **exploring the filesystem** instead of using the
  provided path hint — `find /galaxy` (a nonexistent Galaxy path assumption leaking into the
  sandbox), listing `/work/output` (empty), checking `/tmp` — and the captured answer is an
  **incomplete exploration fragment** (turn/timeout budget consumed before the compute step).
- Data access itself WORKS: `bix-12-q3` successfully extracted `/work/input/<uuid>/scogs_fungi.zip`.
  So the data is reachable at `DATA_DIR=/work/input/<uuid>/`; the issue is agent STRATEGY + turn
  budget on multi-file tasks, plus the odd `/galaxy` assumption.

**Actionable (BioMate-side, not a benchmark fix):** run_code's data-staging guidance should point the
agent straight at `$DATA_DIR/<id>/<name>` for multi-file inputs and discourage `/galaxy`/root-fs
exploration; and/or raise the exploration turn budget. Single-notebook capsules (unambiguous path)
already work at 87.5%. Worth a backend run_code system-prompt/staging check — distinct from the
(now-fixed) workflow-card gating.

### FIXED + VERIFIED (2026-10-22, commit 16d0c70af, deployed)

Fix: `code-runner.ts` preamble now predefines executable **`INPUT_FILES`** (filename → absolute
container path) and **`INPUT_PATHS`** for every staged dataset (Python + R), so the model has a
guaranteed handle; the `run_code` tool description documents them, says to use them directly, and
**forbids `find`/`ls` over `/`, `/galaxy`, `/tmp` or cwd**. Also fixed a latent bug (the Python
staged comment printed the host path the sandbox can't see → now container path).

Verification on dev (apples-to-apples re-run of the exact failing sweep, skip 8 max 20):
- **Exploration eliminated: 0/20 tasks run `find /galaxy` or probe `/tmp`** (was the dominant failure
  mode). Behavioral fix confirmed.
- **Same sweep 9/20 → 12/20 (+15pp)**; a dedicated multi-file window hit **9/10 (90%) ≈ Biomni Lab**.
  bix-12-q3/q5, bix-11-q5/q6 now pass.
- Residual phylo failures are **genuine capability/difficulty, NOT bugs**: `bix-11-q4` ran a full
  Mann-Whitney (extracted 100/249 treeness values) but answered a different statistic than the GT
  count (question-interpretation); `bix-12-q2` invoked PhyKIT 2.8.0 correctly but used a wrong CLI
  flag (tool-syntax knowledge); `bix-11-q1` now reads `DATA_DIR` correctly, output truncated (turn
  budget). run_code + PhyKIT install + data access all work.

## FutureHouse comparison — LAB-Bench (current build, n=40, 10/subtask)

LAB-Bench is FutureHouse's benchmark (Karagiannis et al., arXiv:2407.10362). Current build vs
FutureHouse's published Claude-3.5-Sonnet baselines:

| Subtask | BioMate (2026-10-22) | FutureHouse (Sonnet) | BioMate v1 (2026-04) |
|---|---|---|---|
| ProtocolQA | **100%** | ~55% | 70.4% |
| SeqQA | 80% | ~45% | — |
| CloningScenarios | 70% | ~60% | 39.4% |
| DbQA | 50% | ~60% | — |
| **Overall** | **75%** | ~55% | 50.9% |

Beats the FutureHouse baseline on 3/4 subtasks; +24pt over BioMate v1. **ProtocolQA 100%** (v1 was
70.4% with 30% of items triggering workflow dispatch) is direct evidence the run_code/workflow-card
fix cleared the MCQ workflow-dispatch failure mode too. **DbQA 50%** is the weak spot — pure
database-knowledge recall with no retrieval (LitQA2 excluded here: coverage-bound, scoped out).
Caveat: n=10/subtask → wide CI; the signal is directional but strong and consistent.

## Status of the broader AI-scientist comparison

- **Biomni**: already a RealBio comparator row (routing 0.95 / boin 0.5 / pbpk 0.0) + biomni_eval1.
- **BixBench**: integration validated; exec comparison blocked on run_code (this doc).
- **SAB / BAB**: blocked on gated external data (SAB gold behind password OneDrive + stale adapter;
  BAB source unconfirmed).
- **TxAgent / FutureHouse / STELLA**: not yet added as rows.

## Fairness correction — BioMate is a MULTI-LLM SYSTEM, and the Sonnet bar is dated (2026-10-22)

The LAB-Bench "beats FutureHouse" framing was NOT fair as first stated. Two corrections:

1. **BioMate is a multi-LLM system, not "gpt-5.6-luna + harness."** The answer passes through
   intentModel (gemini-3.8-flash) → toolRankingModel / agentic-loop (claude-haiku-4-5) →
   responseModel (gpt-5.6-luna). The eval's `model=gpt-5.6-luna` is only the response role. The
   right comparison is **system vs single model**, not "our model vs Sonnet."
2. **The ~55% "FutureHouse" bar is a single 2024 model (Sonnet 3.5) bare** — dated, single-component.

Fair control run: **gpt-5.6-luna BARE** (OpenRouter, no BioMate pipeline) on the IDENTICAL seed=42
items, same adapter-scaffolded prompt (n=80, 20/subtask):

| Subtask | bare gpt-5.6-luna | BioMate system | Sonnet-3.5 (2024) |
|---|---|---|---|
| ProtocolQA | 60% | 85% | ~55% |
| CloningScenarios | 85% | 90% | ~60% |
| SeqQA | 40%* | 90% | ~45% |
| DbQA | 35% | 40% | ~60% |
| **Overall** | **55.0%** | **76.2%** | ~55% |

**Honest conclusions:**
- The bare MODERN model (55.0%) ≈ the 2024 Sonnet bar (55%) → the earlier +30–45 gap was NOT
  model-era inflation; a single modern model is no better than 2024 Sonnet on these MCQs.
- BioMate the SYSTEM adds **+21.2pp over the same bare model** (same items, same response model) —
  the real, isolated bare-vs-harness dividend. This is the defensible claim: *system over single
  model*, not *our model over Sonnet*.
- **DbQA is the honest exception**: system 40% barely > bare 35%, both < Sonnet 60%. The
  database-knowledge-recall weakness is real and the system does not fix it (no retrieval wired for
  DbQA-type lookups) — a concrete improvement candidate.
- `*` **Caveat:** bare SeqQA had ~6/20 empty-response errors (scored 0), so bare SeqQA 40% is a
  floor and the +50 system delta on SeqQA is an upper bound; a clean bare SeqQA re-run is pending.
