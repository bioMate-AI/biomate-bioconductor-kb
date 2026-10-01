# VerificationLayer — harness strengthening (2026-10-01)

New module `backend/lib/galaxy/ai/verification_layer.py` (stdlib-only, Python-3.9-safe, 7/7 unit tests in
`backend/tests/test_verification_layer.py`). Formalizes the *generation-time* verification the harness was
missing — the moat is the harness (grounded + executed + VERIFIED), per the Aviary result (open/small agents
match frontier at ~100× lower cost via environment + inference-time verification) and the enterprise-agent
review ("formalize the QC loop as a first-class VerificationLayer").

## Primitives (model-agnostic; IO injected as callables → unit-testable, provider-agnostic)
- `majority_vote(samples)` / `self_consistent(generate,k,workers)` — self-consistency: modal answer + confidence.
  Free accuracy on hard tasks by sampling K and voting.
- `verified_sample(generate, verify, k)` — pass@k ORACLE: return the first sample a DETERMINISTIC verifier
  accepts (schema-valid / runs on Batch / grader==gold). Any correct rollout is retained.
- `consensus(answers, min_agree, fuzzy_threshold=None)` — do N independent answers agree? EXACT normalized
  match for terse answers (routing names, params, labels); salient-F1 fuzzy clustering for PROSE (two teacher
  LLMs phrasing a finding differently). (This is exactly the dual-teacher CoT-distillation keep rule — reusable.)
- `grounded_pick(answer, candidates)` — grounded-by-construction: map a free-form selection to the PROVIDED
  candidate it names (exact then containment), else None. Returns the canonical catalog id. None = the harness
  refusing an off-catalog hallucination.

## Why additive / safe
New file, stdlib-only → cannot crash the Galaxy import chain; no edit to churned core files (worktree-safe).
Not yet wired into hot paths (no deploy risk this session).

## Wiring follow-ups (sequenced)
1. `grounded_pick` → routing/lane/model-selection output boundary (reject off-catalog at the harness, not the model).
2. `self_consistent` → hard generative tasks (findings/decomp) at inference; report confidence to the UI.
3. `verified_sample` → param-generation (verify = schema-valid / runs on Batch) and L2 tasks.
4. `consensus` → refactor `build_cot_distill.py` to call `vl.consensus(..., fuzzy_threshold=0.4)` (dedupe the
   ad-hoc consensus logic there).
Each wiring touches backend Python → run the pre-sync checklist (tsc/vitest + `import galaxy.ai.<mod>`), then sync.
