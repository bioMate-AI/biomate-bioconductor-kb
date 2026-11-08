# Handoff — Harness2 + ScienceBuddy RSI / self-improvement adoption work

**Date:** 2026-10-21
**Purpose:** hand this thread to another session (the originating session is now on the drug-dev benchmark series). This doc is a **cold-start resume point** — everything needed to pick up without the prior session's context.
**Aliases used by the user:** "researchbuddy" = **ScienceBuddy**; "xx2" = **Harness2**.

---

## 1. What this thread is

Two linked external **recursive-self-improvement (RSI)** digs and their BioMate adoptions:

- **Harness2** (Google, arXiv:2610.14224, Apache-2.0) — verifier-free **Propose-Probe-Compose** harness self-improvement (improve the agent's *harness*, not its weights). Vendored + adapted.
- **ScienceBuddy** (arXiv:2609.17523, MIT) — **recursive-in-recursive** self-improvement: inner loop evolves a `run(task, api)` harness (Val-gated), outer loop GRPO-trains the model under it. Dug, necessity-audited, and selectively adopted.

Both land in the prototype self-improvement loop (`grounded-prototype/research/`) plus one on-prem-training adoption (the export-and-verify gate). The unifying BioMate thesis: **harness-primary + verifiers + gated self-improvement**, with the model as one trainable component.

---

## 2. Current state — DONE and where it lives

**Branch/topology (IMPORTANT):** everything is merged into **biomate-review's branch `cursor/tutorial-live-recording-and-report-editing-4ea7`** (the canonical working tree at `/Users/kky/biomate-review`). It also exists on the `grounded-harness2` worktree (`/Users/kky/biomate-review/.claude/worktrees/grounded-harness2`) and on a clean `integration/next-phase`-based cherry-pick branch `grounded-land-20261020` (`/Users/kky/biomate/.claude/worktrees/grounded-land-20261020`) if a next-phase landing is ever wanted. Key merge: **`d7b13a20f`** (ScienceBuddy adoptions).

| Piece | Where | Status |
|---|---|---|
| Harness2 dig + BioMate audit + proposals | `docs/20261019_HARNESS2_DIG_AND_BIOMATE_FIT.md` | done |
| ScienceBuddy dig + **necessity audit** (+ impl log §7) | `docs/20261020_SCIENCEBUDDY_DIG_AND_BIOMATE_NECESSITY_AUDIT.md` | done |
| Decomposition + feedback design | `docs/20261019_DECOMP_ORCHESTRATION_AND_FEEDBACK_DESIGN.md` | done |
| Prototype self-improvement loop (P0 verifier bridge, P1 skill-improve, B2 feedback→reward, A1 decomposition) | `grounded-prototype/research/{verifiers,harness_improver,feedback,decompose,controller,synthesis,h2_biomate}.py` + `research/vendor/harness2/` | done |
| **Stricter selection gate** (held-out Val, zero-error, strict-improve, no-regression) | `grounded-prototype/research/harness_improver.py::propose_probe_compose` | done |
| **Real-scorer bridges** (loop optimizes production metrics) | `grounded-prototype/research/verifiers.py::RealDecompVerifier`, `RealParamsVerifier` + `select_verifier` | done (decomp + param only) |
| **Export-and-verify gate** (on-prem, blocks degenerate adapter promotion) | `evaluation/local_trial/verify_export.py` + `evaluation/local_trial/spot_train.sh` (`gate_adapter` on every served-adapter promote) | done |
| B1 correction-capture UI → live injection | `frontend/client/src/lib/corrections.ts` + `components/chat-message.tsx` (feeds `galaxy-assistant.ts::_buildCorrectionContextBlock`) | done |
| Tests | `grounded-prototype/tests/` — 9 files, **98/98** (CPU) | passing |

**Verification:** prototype suite `cd grounded-prototype && python3 tests/test_{engine,cmc,retrievers,research,harness,verifiers,h2_biomate,feedback,decompose}.py` → 98/98. `python3 evaluation/local_trial/verify_export.py --selftest` → PASS. Frontend B1: `cd frontend && npx tsc --noEmit -p .` (needs the node_modules symlink, see gotchas) + `npx vitest run client/src/lib/corrections.test.ts`.

---

## 3. Necessity verdict (do NOT re-adopt redundant things)

From the ScienceBuddy audit: **most candidate adoptions are redundant** — BioMate already has a provider-enforced command schema, cross-worker durable handoff (`ai/runs/`), a sandboxed rollout loop, its own **TRL** RL stack (GRPO/SFT/DPO), and a rich verifier contract. **Do not import SkyRL** (BioMate has TRL). Genuine gaps were: (a) unified export-and-verify gate — **DONE**; (b) AST/schema validation of generated code — **deprioritized** (the Docker sandbox is the real boundary, low ROI); (c) **wire the dormant self-improvement loop into production** — the big open item (§4).

---

## 4. OPEN / NEXT — what the taking-over session should do

Ordered by value; note which are offline vs live-stack:

1. **#3 — wire the dormant self-improvement loop into production (`pattern_router`).** *(LIVE-STACK; the big one.)* The prototype loop + the real-scorer bridges are built; the gap is wiring to the live composer. `pattern_router` is flag-OFF (`BIOMATE_PATTERN_ROUTER_ENABLED`) and the prototype `research/` is **not imported by `backend/`** — dormant by construction. This needs the dev-stack verification loop + the UX E2E audit (it touches the live chat path); **do not do it blind offline.** Design: `docs/20261019_DECOMP_ORCHESTRATION_AND_FEEDBACK_DESIGN.md` Part A + `docs/20260826_BIOMATE_LLM_MATRIX_STATUS.md` / `pattern_router.py`.
2. **More real-scorer bridges** — *(offline.)* Only decomposition + param-prefill are bridged. **admet/routing are NOT cleanly bridgeable** (admet `score_admet_case` needs structured predicted/reference dicts; routing `score` is task-coupled) — the mirror stays there; don't force it. Pattern to copy: `verifiers.py::real_decomp_verifier` (importlib-load the real scorer, graceful fallback).
3. **B1 browser UX-audit** — *(gated dev run.)* Verify the disambiguation-pick → correction → next-turn-injection round-trip on dev per the UX E2E Completeness Standard.
4. **Export gate** — the class is closed (all served-adapter promotes gated). Optional: a post-build reload check in the eval path.

---

## 5. Key decisions / gotchas (so you don't relearn them)

- **Branch discipline:** biomate-review is a **shared worktree with concurrent committers** — plain commits only, no `--amend`, no `git add -A` after a conflicted merge; commit explicit paths so you don't sweep others' uncommitted work (the tree is usually dirty).
- **Worktrees aren't `npm install`ed** — to run `vitest`/`tsc`, symlink: `ln -s <main>/frontend/node_modules <worktree>/frontend/node_modules` (gitignored; package.json is identical).
- **No speculative GPU** — `verify_export.py`'s model-load path is reviewed, not run; it has a CPU `--selftest` for the degeneracy contract. Don't launch the GPU path to "see if it works."
- **Export gate is fail-closed** with a `VERIFY_EXPORT=0` escape hatch; it gates every `aws s3 cp .../_adapter/` with that adapter's REAL base (SFT→original, DPO→`sft_merged`, full→`base_domain` via `PROMOTE_BASE`).
- **Real-scorer bridge import** needs the repo root on `sys.path` for adapters that do `from evaluation.core...` (param_prefill_adapter); the decomp scorer is stdlib-only (spec-load works directly).
- **Classifier/permission:** a bulk `git cherry-pick` of many SHAs was denied by the auto-mode classifier once; if you hit it, have the user run it via `!` or add a Bash permission rule — don't split-to-evade.

---

## 6. Memory + reference pointers

- `reference_sciencebuddy_dig` (the necessity verdict + commits), `project_grounded_standards_assistant` (the grounded-prototype engine/MCP/panel + this loop), `project_llm_harness_task_split`, `feedback_audit_biomate_capabilities_first` (the recurring "gap is wiring not primitive" lesson).
- Harness2/ScienceBuddy clones: ScienceBuddy at `/Users/kky/sciencebuddy-dig` (MIT); Harness2 vendored in `grounded-prototype/research/vendor/harness2/` (Apache-2.0).

---

## 7. One-line status for the new session

*The Harness2 + ScienceBuddy adoptions are DONE and merged (prototype loop with stricter selection + real-scorer bridges, the on-prem export-and-verify gate, B1 correction UI). The one substantial open item is #3 — wiring the dormant self-improvement loop into production `pattern_router`, which is a live-stack change requiring the dev verification loop (not an offline edit). Everything else open is small/offline. Start from `docs/20261020_SCIENCEBUDDY_DIG_AND_BIOMATE_NECESSITY_AUDIT.md` §7 and this doc.*
