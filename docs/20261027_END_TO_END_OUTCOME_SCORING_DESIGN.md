# End-to-end outcome scoring: a multi-dimensional scorecard for all three benchmarks

**2026-10-27.** Design decision: every task is scored on an **outcome dimension — the end-to-end executed
result, verified against a hidden reference — alongside the component criteria dimensions** that localize where
the chain broke. This is the scoring model the strongest public benchmarks use (SWE-bench's `FAIL_TO_PASS`
outcome plus `PASS_TO_PASS` regression; MLE-bench's held-out metric; ScienceAgentBench's program **and**
execution-result **and** cost), adapted to our three task families. A prototype is built and measured below.

## The principle

A single label ("did it name the right workflow / channel / dose") cannot show platform ability, because a
chat model can produce the label without doing the work. We therefore score each task on:

- **OUTCOME (primary, end-to-end):** the executed result matches a **hidden** reference — a resumed run passes
  hidden checks; the retrieved record is correct; the computed value is within tolerance. This is the headline.
- **Component dimensions (diagnostics):** the per-stage criteria (route, parameters, computation fidelity,
  safety, regression) that say *where* a failed outcome went wrong. Kept as diagnostics, not the headline.

A low outcome with a high component score and a low outcome with a low component score mean different things —
"applied the rule wrong" vs. "never modeled the problem." Scoring both, end-to-end, is what makes the result
diagnostic instead of a single opaque number.

## Per-benchmark scorecard

| Benchmark | Component dimensions (diagnostic) | OUTCOME (primary, end-to-end, hidden) |
|---|---|---|
| **RealBio** | route correct · parameters correct · fix category correct | **resumed run passes hidden output checks AND breaks nothing that worked** (SWE-bench pattern) |
| **Channel routing** | channel label correct | **correct record retrieved / compatible accession / workflow actually initiated** (downstream success) |
| **DrugDev** | task identified · inputs extracted · **exposure–response fidelity** · safety | **selected dose within tolerance of the hidden toxicity reference** (operating-characteristic outcome) |

## Working prototype — the dose-decision scorecard

Implemented and measured on the 20 Phase-I scenarios. The system receives PK and exposure–response inputs and a
dose grid with the **true toxicity curve hidden**, and must return the per-dose toxicity it models, the selected
maximum tolerated dose, and a no-safe-dose flag. Three dimensions, each in [0, 1]:

- **outcome** (primary): selected dose within one level of the hidden reference (or a correct no-dose call);
- **safety**: correct no-safe-dose declarations and no selection above the elimination band (no overdose);
- **fidelity** (diagnostic): fraction of dose levels where the modeled toxicity is within two-fold of truth —
  i.e. *did the system actually model exposure–response, or guess?*

**Scorecard (outcome | safety | fidelity):**

| System | outcome | safety | fidelity |
|---|---|---|---|
| **Mechanistic pipeline (execution reference)** | **0.90** | **0.90** | **1.00** |
| Claude Opus 5 | 0.50 | 0.45 | 0.46 |
| Gemini 3.1 Pro | 0.25 | 0.30 | 0.16 |
| GPT-6.1-sol-pro | 0.10 | 0.20 | 0.01 |

The mechanistic pipeline — the platform path that computes the exposure–response curve and applies the
selection rule end-to-end — sets the reference at 0.90 / 0.90 / 1.00. The diagnostic value is the **fidelity**
column: GPT-6.1-sol-pro's outcome is 0.10 *because* its curve fidelity is ~0.01 — it never modeled the
exposure–response and effectively guessed; Opus-5 modeled the curve partially (fidelity 0.46) and got half the
outcomes; the pipeline computes the curve (fidelity 1.00) and lands the outcome at 0.90. Scoring the outcome
end-to-end **alongside** fidelity is what separates a system that *computes* the answer from one that *guesses*
it — a single outcome number alone would not have shown the cause.

## Rollout

1. **Dose-decision scorecard** — built and measured (this document).
2. **RealBio autofix → execution outcome** — give a failed workspace with the diagnosis withheld; the system
   submits a corrective artifact; a hidden validator checks the specific failure is resolved and nothing else
   broke. Component dimension (category) kept as a diagnostic.
3. **Channel routing → downstream success** — score whether the chosen resource actually returns the right
   record / initiates the right workflow, not just the channel label.

Each rollout keeps the current label/selection score as a **diagnostic dimension** and adds the hidden,
executed **outcome** as the primary — so no existing measurement is lost, and the headline becomes what the
system *did*, not what it *named*.
