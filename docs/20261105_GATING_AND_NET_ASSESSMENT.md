# Gating (both senses) + honest net assessment of today's work

Date 2026-11-05. Answers: how changes are gated, what each gate does and what happens on pass/fail,
and whether today's work genuinely improved BioMate or just added complexity.

---

## Part 1 — My verification gates (how a change reaches dev)

Every code change passes these before it is committed / pushed / deployed. A failing gate STOPS
the pipeline; the rule is read-the-full-error → fix the root cause → re-gate (never retry blind,
never commit on red).

| Gate | Command | Catches | On FAIL |
|---|---|---|---|
| 1. Type check | `cd frontend && npx tsc --noEmit -p .` | wrong types, missing imports, prop-shape mismatches, broken refactors | fix before any commit |
| 2. Targeted tests | `npx vitest run <touched suites>` (~3–9 s) | regressions in the changed component/route | fix code; or if the test encoded a bug, correct the test + say why |
| 3. Full suite | `npx vitest run` (193 files / 2179 tests, ~90 s) | cross-file regressions from a change | isolate + fix before push |
| 4. Pre-sync checklist | tsc + full vitest + `python3.9 -c import <modified galaxy module>` + fabrication/chain audit if DB/`.nf` changed | Python module-load failures (PEP 604 on 3.9), fabrication-class workflow bugs | fix before `sync_to_dev.sh` |
| 5. Post-sync smoke | `GET /api/version` (workers up = no crash-loop) + the specific changed behavior live | a deploy that "said OK" but crash-loops or didn't land | read the full sync log; roll back (in-place) |

Why this discipline: documented incidents (Galaxy crash-loop from a 3.9 union annotation; a sync
that reported OK but never deployed; today's `git gc` filling the disk) all trace to acting on a
truncated signal instead of the full error. The gate is the forcing function to read the full
error first.

What each gate guarantees: **green tsc** = it compiles and types line up; **green vitest** = no
asserted behavior regressed; **post-sync smoke green** = the live service actually behaves as the
local tests said. None of these prove scientific correctness of a workflow — that needs the
BioMate QC gates below and live domain runs.

---

## Part 2 — BioMate's own QC gates (the product gates audited today)

Each workflow writes `qc_metrics` / `qc_events`; the QC engine reads them, compares each metric to
its threshold, and classifies the gate. What happens per outcome:

| Outcome | Meaning | What happens |
|---|---|---|
| **PASS** (green) | metric within threshold | run proceeds; recorded as clean |
| **ADVISORY** (amber) | near-threshold, non-blocking | surfaced as a warning; run proceeds |
| **HALT / FAIL** (red) | metric breaches a blocking threshold | blocks; in **auto-loop** mode triggers remediation — propose a param change (was→now), re-run, re-gate (up to N rounds) |
| **NOT_EVALUATED / unavailable / unknown** (gray) | the metric could not be read | must **NOT** read as a pass; surfaced as "could not evaluate" |

Representative gates: DILI (`dili_probability` vs threshold), hERG (IC50 / `herg_inhibition_prob`),
BOIN DLT de-escalation boundary, clintox, Ames, FASTP reads-surviving %, DESeq2/enrichment
significance, cryo-EM FSC/CTF, etc.

The audit found these gates were **not telling the truth**: DILI HALTing on a stale categorical
label instead of the numeric probability; hERG prob-only predictions silently skipped on the
Batch path; FASTP (a sequencing gate) stamped onto clinical runs; zero-gates-evaluated reported as
a GOLD pass; degraded/unevaluable gates rendered invisible so the run looked all-clear. The fixes:
UI now surfaces degraded gates and colors HALT≠advisory (shipped); the gate-logic corrections are
in the backend review patches (`20261105_BACKEND_PYTHON_REVIEW_PATCHES.md`) for human apply.

---

## Part 3 — Improved, or just complicated? (honest)

**Improved on correctness; NOT simplified — and several bugs are symptoms of the existing
over-complexity.** Breaking it down:

**Genuinely improved (and mostly WITHOUT adding complexity):**
- Real wrong-answer bugs fixed and verified: findings no longer show the wrong run's results; DESeq2
  findings no longer come back empty on BioMate's own TSV; variant MODIFIER no longer miscounted;
  billing no longer shows all-zeros; degraded QC is no longer invisible; the findings reconciler no
  longer overwrites a correct verdict with an LLM "no liabilities."
- Some changes REMOVED complexity: #3 GEO patch deletes a hardcoded per-study (GSE227835) branch and
  replaces name-guessing with a structural parse; dead sidebar code flagged for removal; a false
  "fix" (S2#8) was rejected rather than adding a wrong change.
- The fixes were narrow (a guard, a field name, a delimiter, a positive match) — not new subsystems.

**Still complicated — and this is the real finding:**
- The bug *class* exists BECAUSE of accumulated complexity. Examples:
  - Findings has FOUR layers (deterministic parsers + LLM fallback + entity descriptors + a
    reconciler + an on-demand sidecar + an in-memory cache). The #4/#5a/#3-S1 bugs all came from
    these layers disagreeing or trusting each other blind. A reconciler that exists only to arbitrate
    two independently-computed verdicts is a complexity smell — the right design is ONE source of
    truth per verdict, not two + a referee.
  - QC had two code paths (live in-process vs completion/S3) that extracted different metrics and
    disagreed (hERG). Two paths that must stay in lockstep is fragile by construction.
  - DILI/BOIN/phase2 used heuristic-seeded aggregates then conditionally overrode them — the
    asymmetric `if/elif` with no `else`, the `(x or 999)` trap. Each is a shortcut that looked simple
    but hid a wrong default.
- My work made these **correct within the existing structure**; it did not collapse the structure.

**Verdict:** today moved BioMate from "silently wrong in ~39 places" toward "honest" — a real
improvement, and net-simplifying in a few spots. But it did not reduce the architectural
complexity that produced the bugs. The highest-leverage NEXT step is **simplification, not more
patches**: one source of truth per findings verdict (retire the dead deterministic ADMET path and
the reconciler), one QC metric-extraction path shared by live and completion, and no
heuristic-seeded aggregate that a later step must remember to fully override. Until then, the same
class will keep recurring — which is exactly why the audit found so many at once.
