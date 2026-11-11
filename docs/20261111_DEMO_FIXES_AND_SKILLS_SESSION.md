# 2026-11-11 — Session summary: demo UI fixes + skills architecture

Overnight autonomous session. Everything below is committed + pushed; nothing is merged to
`integration/tracks-20261111` or live on dev yet (see **Deploy state**).

## 1. Demo UI refinements (from the BACE1 run_code demo screenshots)

Doc: `docs/20261110_DEMO_UI_REFINEMENTS.md`. Five issues:

| # | Issue | Status | PR |
|---|---|---|---|
| 1 | Chinese UI → English example prompt injected (examples are English-only literals) | **NOT done** — needs careful i18n (quality-sensitive); left for review | — |
| 2 | Run Code card: no Copy button, code clipped/no scroll | ✅ Copy button + scrollable viewport | #371 |
| 3 | Claimed plot from run_code never shown | ✅ `code-runner.ts` base64-encodes image outputs (≤4MB) → `<img>` inline | #371 |
| 4 | "Redo as a validated run" button confusing | ✅ Removed (run_code params per-call, no stable workflow mapping); plumbing kept, deferred | #371 |
| 5 | "Adapt the generative model…" → empty dock/ADMET card | **Diagnosed + skills work** (see §3) | #372 |

Earlier demo-bug batch (separate, from the first screenshots): #1 evidence surfacing (#366),
#2 ReINVENT4 procps image (live in ECR), #3 blank panel (#368), #4 chip clutter (#369), + the
consolidating fast-forward (#370).

## 2. Deploy state — ACTION NEEDED (merge, not re-sync)

Dev currently serves the **tracks** line (`279d6d27`+), redeployed by another session —
**which wiped the earlier demo fixes off dev** because they live on side branches, not tracks.
Side-branch syncs keep getting overwritten by the concurrent tracks deploys (a deploy-war). The
durable fix is to **merge the demo-fix PRs into tracks** (gated to you):

- **#370** (evidence / blank-panel / chip-collapse — fast-forward) → then close #366/#368/#369
- **#371** (run_code copy+scroll / render plots / remove verified-run button)
- **#372** (skills architecture — docs + prototype + flag-gated registry; safe to merge, inert)

Once merged, the tracks deploys carry them instead of erasing them. I stopped doing overwrite-able
side-branch syncs.

## 3. Skills architecture for task decomposition (#5) — PR #372

Driven by your design dialogue (inference not keywords; a closed solution-type enum can't be
exhausted; per-pattern presentation; ground in documented SYSUCC directions; "shouldn't there be
skills"; "don't you have the pattern docs"). Doc: `docs/20261111_SKILLS_ARCHITECTURE_TASK_HANDLING.md`.

**Key findings (reuse, don't reinvent):**
- Pattern skills **already exist** — the 13-entry chain pattern library
  (`docs/20260608_CHAIN_PATTERN_LIBRARY_DRAFT.md` + `chain_composer/pattern_loader.py`), whose
  stated purpose IS this design ("taught about via retrieval, not picked from via enum").
- `pattern_router.py` + `chain_composer` + the `SkillManager`/`SkillLoader` skill framework all
  exist but are **off/shadow/prompt-only and not wired into the live chat decomposer**
  (`galaxy-assistant.ts` monolith). Per `20261009_ORCHESTRATION_CAPABILITY_AUDIT`, the problem is
  **integration**, not missing components.
- "Adapt the generative model to our chemical series" is **verbatim** a documented SYSUCC
  capability (BD doc §5.4 Models→Adapt; §7.3 generator adaptation; §7.2 → a model-version card).
  The product currently fails its own BD promise.

**Delivered + measured:**
- `backend/lib/galaxy/ai/skills/generator-adaptation.md` — first operation skill (validated
  against SkillManager).
- `frontend/server/operation-skills.ts` — Node operation-skills registry wired into the
  decomposition prompt, **flag-gated `OPERATION_SKILLS_IN_DECOMP`, default OFF** (inert; same
  discipline as pattern_router/ml_training). Unit-tested (4/4).
- **Offline A/B** (gemini-3.8-flash, flag off vs on): "adapt the generative model" flips from
  `workflow_generation` (fabricated REINVENT4/catalog pipeline — the misroute) to a distinct
  `generator_adaptation` intent, `needsWorkflowGeneration=false`. **Decomposition misroute fixed.**
- **Gold-set regression check** (24 rows, structural): 19/23 identical, 0 errors, 4 node-count
  increases (inconclusive — no noise baseline). Flag stays OFF pending the formal judged eval.

**Not done (needs your steer — product + feature + spend):**
1. Route `generator_adaptation` to the Models/`ml_training` generator-adaptation path and render a
   **model-version card** (§7.2). Currently it degrades to an LLM text answer (safe, but not the
   real card).
2. Build the missing **small-molecule generator-adaptation branch** in `ml_training` (today it has
   single-cell diffusion / protein diffusion / LLM branches, no ReINVENT-style small-molecule one).
3. Formal judged eval (`decomp_judge.py`, ~$2–4) + off-twice noise baseline + adequate max_tokens,
   as the gate before enabling the flag.
4. Peel each monolith capability/pattern section into its own skill; wire the existing pattern
   library + pattern_router into the live decomposer (the integration the 20261009 audit calls for).

## 4. Memory written
- `feedback_infer_solution_type_not_keywords` — route by inference, retire regex/verb gates.
- `project_skills_architecture` — the skills direction + what exists + migration.

## 5. Housekeeping
- Freed disk (ENOSPC) via your `~/.cache` cleanup; restored 15 tracked figure files that the
  cleanup had removed alongside the untracked diagnostics.
- Shared-worktree: another session (`codex/zh-en-ui-parity`) has uncommitted changes here; I
  committed only my own files by path throughout.
