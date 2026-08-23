# Failure communication — stratification & design (2026-08-23)

**Question this answers:** when a run fails, does BioMate retry? How does the
conversation go when it *can't* fix it alone and needs the user to supply
something? What's the right communication for each failure class?

## 0. Correction to the record

An earlier note called BioMate's failure messaging "weak." That was wrong at the
model level. BioMate already has a **fully stratified failure-guidance system**:

- `backend/lib/galaxy/ai/workflow_ops/autofix/` — **18 specialized fixers**
  (`aws_resource`, `container_error`, `cpu_resource`, `data_file`, `docker_daemon`,
  `file_format`, `nextflow_parameter`, `parameter_validation`, `reference_genome`,
  `retry_strategy`, `samplesheet`, `tool_error_patterns`, + LLM fixers).
- `autofix/user_guidance.py` — a **three-way `FixStrategy`** with **9
  `IssueCategory`s** and a **25-entry knowledge base**, each with a
  `problem_summary`, prioritized `recommended_actions` (steps, external resources,
  est. time, success probability, impact, recommendation level), and
  `auto_attempted_fix`.
- QC auto-loop — mid-run gate failures already remediate with a was→now diff and
  `halt`/`advisory` severity (`nextflow_executor.py:3164`).

**The real problem is integration, not design:** none of `UserGuidance` /
`recommended_actions` / `fix_strategy` is emitted in the run-status payload or SSE
that the panel consumes (`nextflow_executor.py` grep = empty). The panel renders
only the thin classifier (`{user_message, is_transient, suggested_action}` + one
button). So a rich, stratified guidance object is computed and then dropped on the
floor. That is why a real failure reads as a generic one-liner.

## 1. The three tiers (already in the model) × how the conversation should go

| Tier | `FixStrategy` | Categories | Who acts | Retry? |
|---|---|---|---|---|
| **T1 Auto-fix** | `AUTO_FIXABLE` | param missing/wrong, resource insufficient | BioMate | Yes — fix + `-resume`, cap 3 |
| **T2 Needs you** | `USER_ACTION_REQUIRED` | data quality/format, missing reference/license, ambiguous choice | User supplies 1 thing, then BioMate resumes | Yes, *after* input |
| **T3 Dead-end** | `NOT_FIXABLE` | container, permission, system bug | Neither (escalate) | No — re-run repeats the failure |
| **T4 Code defect** | *(new class)* | bug in the `.nf`/R/Groovy workflow code | BioMate (owns it); user never fixes code | Only after a **validated** patch — generated wf; curated wf → report + alternative |

### T1 — Auto-fix (BioMate retries; user is *informed*, not asked)
- **Trigger:** a fixer matches the error (e.g. `nextflow_parameter_fixer` sees an
  out-of-range value; `cpu_resource_fixer` sees OOM/137).
- **Conversation:** an inline, non-blocking progress line in chat, in the SAME
  folded-progress lane as the QC remediation card — showing the was→now change and
  the attempt counter:
  > `qc` · Detected out-of-memory on `STAR_ALIGN` → raised memory 16→32 GB, resuming (attempt 2/3).
- **Panel:** overall badge stays `running`; no failure buttons. Expandable
  "what changed" reveals the `auto_attempted_fix` diff.
- **Escalation:** if the cap (3) is hit without success, the item **promotes to
  T2 or T3** — never silently loops. The chat says so: "auto-fix didn't resolve it
  after 3 tries — here's what I need from you / why this can't be re-run."

### T2 — Needs you (the case you asked about — this is the missing loop)
- **Trigger:** `USER_ACTION_REQUIRED` — the error needs a decision or an artifact
  BioMate cannot infer: a malformed/absent input file, a missing reference genome
  or license, a genuinely ambiguous scientific choice, or a param only the user
  knows.
- **Conversation — a structured *request*, not an error dump.** Four parts, all
  already present as fields in `UserGuidance`:
  1. **What happened, in one plain line** (`problem_summary`) — e.g. "The GTF
     annotation is missing `exon_number` on 4,102 exons, so `iCount` can't run."
  2. **Why I need you** — one sentence on why BioMate can't decide this itself.
  3. **Prioritized options** (`recommended_actions`, ranked ★): each with its
     steps, est. time, success probability, and *impact* — so the user picks with
     the tradeoff visible (e.g. "① re-download the Ensembl GTF (5 min, 99%) vs
     ② drop the 4,102 exons and proceed (instant, changes results)").
  4. **An inline affordance to satisfy it and resume** — the piece that does not
     exist today. Reuse the **existing pre-run param-clarification / disambiguation
     card** (`testInjectParamClarification`, `DisambiguationCard`) mid-run: an
     upload slot / dropdown / confirm-choice control right in the chat. On submit →
     patch the run → `-resume`. No context switch, no "go do this elsewhere then
     restart from scratch."
- **Panel button:** `Provide & resume` (or `Fix & resume`). Never a bare
  "Resume from last step" — that implies BioMate can retry unaided, which is false
  for T2.
- **State:** the run parks in a distinct `awaiting_input` state (not `failed`,
  not `running`) so the UI, counts, and SSE all reflect "waiting on you," and a
  reload restores the request card.

### T3 — Dead-end (honest; no false hope)
- **Trigger:** `NOT_FIXABLE` — a container that won't start, a permission/quota
  wall, a genuine platform bug. Re-running reproduces it.
- **Conversation:** clear plain-language cause (classified, never the raw
  Nextflow/JSON log), an explicit "this isn't something a re-run will fix," and a
  real next step — report to us (attach the sanitized run id), switch tool, or
  adjust the experiment. Offer **"Report this run"** (one click, ships the
  sanitized diagnostic to support), not a "Resume" button that will just fail again.
- **Panel button:** `Report` / `Start over` only. `canResumeFailed = false`.

## 1b. T4 — Workflow-code defect (BioMate's fault, not the user's)

The three tiers above assume the *pipeline is correct* and something around it
(params, data, infra) is off. But the workflow's **own code** can be buggy — a
`.nf` process script, embedded R/Python, or Groovy channel logic: a GString
compile error, an R-escaping bug, a wrong column reference, a logic error.

**This is a distinct class, and today it is the least-handled one.** Confirmed in
code: the 18 fixers repair params/resources/data/samplesheet/reference — **none
edit workflow code**. `propose_validate` checks at *generation* time (schema/LLM),
but there is **no compile/`-stub`/lint gate**, so code bugs reach runtime, fall to
the generic classifier, and re-running repeats the crash. The accession-benchmark
GString-compile / R-escaping fixes (GSE22055, "6 stacked execution-path fixes")
were caught by a human fixing the canonical file — not by the system.

**Ownership:** BioMate. The user must *never* be asked to fix workflow code, and
the communication must own it: *"This is on our side — the workflow step has a
defect. Your inputs were fine."* "Resume from last step" is wrong here (re-runs
the bug).

**The danger that makes this the scariest tier:** a code bug can fail **loud**
(crash) or **silent** (runs green, wrong numbers). Auto-rewriting the failing
process to "make the error go away" is the runtime version of the forbidden
"make the test pass by breaking the system" — it can produce plausible,
corrupted science. So an auto code-fix is only legitimate if it is **re-validated
against the same QC/biology gates** the run already carries. A repaired run that
now "succeeds" but no longer passes those gates means the patch is suspect.

**Fork by provenance (the executor already knows which):**

- **Generated workflow** (biomate_entry / regenerated bioc / chain-composer):
  BioMate *may* attempt a **code repair** — but this capability **does not exist
  yet** and is the risky frontier. Required guardrails: (1) propose a patch;
  (2) **validate by re-compiling and re-running the failed process on the cached
  inputs** (a real stub/re-exec, not LLM self-review); (3) show the **code diff**;
  (4) auto-apply + resume **only** for demonstrably non-scientific fixes (syntax,
  GString escaping, IO plumbing) — anything touching result logic needs
  confirmation; (5) **re-assert the QC/biology gates** on the output after the
  patch; (6) cap attempts, then escalate. Feed a successful, validated repair back
  into the generator so the same bug isn't re-emitted.
- **Curated / indexed workflow** (nf-core, DB row): **do not hot-patch per run** —
  that forks the canonical asset, masks a systemic bug hitting every user, and
  violates root-cause discipline. Instead: **file a platform defect** (auto-capture
  workflow id + failing step + sanitized error + input contract), tell the user
  honestly *"this pipeline has a bug on our side; we're fixing it,"* offer an
  **alternative route** (a sibling workflow, or the compute/`run_code` lane), and
  optionally notify-when-fixed. This is exactly the accession-benchmark path —
  fixed centrally, committed, re-validated — made a first-class, user-visible flow
  instead of a manual scramble.

**Communication:** owns the fault, shows the diff if a repair is proposed, never
offers a plain "Resume." Buttons: `Apply fix & re-run` (generated, *after*
validation) / `Report & try an alternative` (curated). Add a **`-stub`/compile
pre-flight gate** so most code bugs are caught *before* a paid Batch run, not
after.

## 2. Why the current screenshot looked bad (root-caused)

The failed ADMET run I audited hit an error **not in the 25-entry KB**, so it fell
through to the generic classifier's `category: unknown` → "The run stopped before
completing…" + a "Resume from last step" button whose label contradicted the
"change something first" guidance. Three distinct bugs, all downstream of the same
root: **the KB/`UserGuidance` path isn't consulted for the live run-status, and the
button isn't derived from `fix_strategy`.**

## 3. The wiring to close it (code, no new model needed)

1. **Emit** `UserGuidance.to_dict()` in the run-status payload + the failure SSE
   event from `nextflow_executor.py` (call the autofix classifier on terminal
   failure; attach `fix_strategy`, `recommended_actions`, `auto_attempted_fix`).
   Keep sanitization (already in place) around it.
2. **Map, don't duplicate:** my thin `_classify_failure` should defer to
   `IssueCategory` (25 KB entries) and only fall back to `unknown` when the KB
   truly has no match — and even then return a *category*, not a shrug.
3. **Render a stratified failure panel** in `nextflow-workflow-viewer.tsx`:
   - T1 → auto-fix transcript in the progress lane (was→now, attempt N/3).
   - T2 → the request card with the four parts + **inline affordance** (reuse
     `DisambiguationCard`) → `POST /rerun` on submit.
   - T3 → honest dead-end + `Report this run`.
4. **Derive the button from `fix_strategy`**, not from `suggested_action` alone:
   T1 none · T2 `Provide & resume` · T3 `Report`/`Start over`. Kills the
   label/guidance mismatch.
5. **Add the `awaiting_input` run state** so T2 parks cleanly and survives reload.

## 4. For claude-design

Two new visuals to design (self-contained brief to follow):
- **T2 "request" card** — the mid-run human-in-the-loop ask: summary + ranked
  options (with impact) + inline provide-and-resume control. Must read as *"I need
  one thing from you,"* not *"error."*
- **T1 auto-fix transcript** — the reassuring "I caught this and I'm handling it
  (attempt 2/3)" line, visually distinct from a failure.

## 5. Honesty note

I have **not** yet verified this end-to-end on a live failing run (needs one Batch
run to trip a real KB category and watch the guidance surface). The model and KB
are confirmed present in code; the not-wired gap is confirmed by grep. The T2
inline-affordance is a genuine build, not just a wiring fix.
