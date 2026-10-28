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

- **outcome** (primary): **exact** selected-dose match to the hidden reference (identical to the benchmark's own dose scorer; adjacent-dose is not credited);
- **safety**: correct no-safe-dose declarations and no selection above the elimination band (no overdose);
- **fidelity** (diagnostic): fraction of dose levels where the modeled toxicity is within two-fold of truth —
  i.e. *did the system actually model exposure–response, or guess?*

**Scorecard (outcome | safety | fidelity):**

| System | outcome | safety | fidelity |
|---|---|---|---|
| **Mechanistic pipeline (execution reference)** | **0.85** | **0.90** | **1.00** |
| Claude Opus 5 | 0.30–0.40 | 0.75 | 0.46–0.64 |
| GPT-6.1-sol-pro | 0.10 | 0.20 | 0.01 |

(exact MTD match; single-run LLM outcome at n=20 is noisy, so LLM rows are ranges; Gemini re-run pending)

The mechanistic pipeline — the platform path that computes the exposure–response curve and applies the
selection rule end-to-end — sets the reference at 0.90 / 0.90 / 1.00. The diagnostic value is the **fidelity**
column: GPT-6.1-sol-pro's outcome is 0.10 *because* its curve fidelity is ~0.01 — it never modeled the
exposure–response and effectively guessed; Opus-5 modeled the curve partially (fidelity ~0.5–0.6) and still landed only a third to two-fifths of the
exact doses; the pipeline computes the curve (fidelity 1.00) and lands the outcome at 0.85. Scoring the outcome
end-to-end **alongside** fidelity is what separates a system that *computes* the answer from one that *guesses*
it — a single outcome number alone would not have shown the cause.

## Rollout

1. **Dose-decision scorecard** — built and measured (this document).
2. **RealBio autofix → execution outcome** — **built and validated.** The fix-hint lines are redacted from the
   error log so the system must *infer* the remedy; it returns a corrective artifact (category + fix + corrected
   parameters); and a hidden, item-specific validator — distinctive resolution tokens auto-extracted from the
   reference fix, plus value/version/numeric checks for the deterministic categories — decides whether the fix
   actually **resolves the specific failure**, while a safety check flags scientifically-wrong fixes (e.g.
   dropping confounded samples, matching the wrong reference build). Validator calibration on the 100 items:
   **96/100 oracle recognition** (recognizes a correct fix) and **0/100 false positives** (a wrong fix from
   another item never scores as resolving). The category label is retained only as a diagnostic dimension. **Caveat:** in the live run the category was emitted as free text and matched crudely, so its 0.20–0.40 figure understates classification and is not a fair score — the constrained-choice category task scores 0.77–0.95 elsewhere; only the **outcome** dimension is validated and should be read as a capability number. A
   worked example: a frontier model, given a genome/index-mismatch failure with the hint redacted, returned
   `genome → GRCh38` and the hidden validator scored outcome = 1, safety = 1. The full cross-model roster is a
   straightforward sweep (gated here only by third-party API latency).
3. **Channel routing → downstream success** — score whether the chosen resource actually returns the right
   record / initiates the right workflow, not just the channel label.

Each rollout keeps the current label/selection score as a **diagnostic dimension** and adds the hidden,
executed **outcome** as the primary — so no existing measurement is lost, and the headline becomes what the
system *did*, not what it *named*.
