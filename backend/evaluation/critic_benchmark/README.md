# critic_benchmark — measuring "BioMate self-corrects"

A RealBio task that turns *"BioMate self-corrects the science"* into a measured number,
built on the committee's correction (`04_llm_critic_eval_review.md` §4,
`00_committee_synthesis.md` §5):

> The RealBio `autofix` task measures failure-**classification** on runs that already
> **crashed** — the easy half. The critic layer's hard job is **silent validity flaws
> in runs that *succeeded***. Those share almost no substrate. The real benchmark must
> be built from **synthetic error-injection into clean runs**, with matched negatives
> and hard negatives, and must report **false-alarm rate** and **harmful-remediation
> rate** as first-class shipping gates — not just precision/recall.

This package does exactly that. It is self-contained (stdlib + the read-only
`galaxy.ai.critics` package), deterministic, uses **no LLM judge**, and runs on
`python3.9`.

## What it measures

For each labeled run it builds a `RunContext` from a stored contract, runs the
registered critics through the **real** post-run hook (`run_critics`, with the
citation + advisory guardrails), and scores what the *target* critic did — **per
archetype, never pooled**:

| metric | definition | role |
|---|---|---|
| **precision** | TP / (TP+FP) | the governance-gating metric |
| **recall** | TP / (TP+FN) | coverage |
| **false-alarm rate** | FP / (clean items) | the crying-wolf gate |
| **harmful-remediation rate** | fired a non-FLAG fix on a valid/hard-neg item / clean | **≈0 hard gate — the clinical red line** |

Each metric carries a Wilson 95% CI (honest small-n bounds).

## The injector set (archetypes)

Each injector takes a clean contract and returns a corrupted one with a known label;
the matched clean contract is the negative. Hard negatives are the look-alikes that
must **not** fire. Every item carries only its target critic's artifact, so only that
critic's `applies_to` passes (clean per-archetype isolation).

| archetype | injector | target critic | hard negative |
|---|---|---|---|
| `design.confounding` | omit a known prognostic confounder (CIE > 10%) | `survival.confounding` **(real)** | a **mediator** that must NOT be adjusted (Table-2 fallacy) |
| `design.batch_imbalance` | batch collinear with condition | `rnaseq.imbalanced_confounding` (WS2 stub) | a **balanced** covariate (not a confounder) |
| `power.epv` | drop replicates below 10 events/variable | `power.events_per_variable` (WS2 stub) | EPV just above the floor (no boundary over-flagging) |
| `qc.threshold` | corrupt a QC metric below its floor | `qc.metric_floor` (stub) | — |
| `output.presence` | drop the primary result from the manifest | `output.presence_floor` (WS2 stub) | — |

The real `survival.confounding` critic is scored **as-is**. The WS2 critics
(Power/EPV, output-presence) and the RNA-seq / QC critics are **stubbed** in
`stub_critics.py` until those branches merge — the harness accepts *any* registered
critic, so swapping a stub for the real one in `build_registry()` is the only change
needed. The stubs are deliberately *correctly designed* so the benchmark's value is
visible against the one critic (`survival.confounding`) with a known weakness.

## Acceptance bar (explicit ship-blocking gates)

Defined in `acceptance.py` (committee §4.4 / §5):

- **HARD GATE (every critic):** `harmful_remediation_rate ≈ 0`. Any analysis-altering
  fix proposed on a valid/hard-negative case fails it — worse than a miss.
- **Per governance tier (precision floor + false-alarm ceiling):**
  `deterministic_auto_apply` ≥0.99 / ≤0.01 · `deterministic_advisory` ≥0.95 / ≤0.05 ·
  `llm_advisory` ≥0.90 / ≤0.05 · `soft_advisory` ≥0.70.
- The declared `governance` is a **ceiling** — precision alone never promotes an
  advisory critic to auto-apply (auto-apply is a deliberate allowlisted opt-in).
- **Clinical context demotes** the bar one notch and forbids auto-apply unconditionally.

A critic **ships** at a tier iff it passes the hard gate and that tier's bar.

## How to run

```bash
# end-to-end: build data → harness arm + bare arm → score → write results
python3.9 -m evaluation.critic_benchmark.run_benchmark --n 20      # from backend/

# just (re)build the deterministic ground truth
python3.9 -m evaluation.critic_benchmark.build_data --n 20

# score an arbitrary predictions file (e.g. a real LLM run) against the ground truth
python3.9 evaluation/critic_benchmark/score.py data.jsonl <predictions.jsonl>

# smoke test
python3.9 backend/tests/test_critic_benchmark_smoke.py
```

Outputs land in `results/critic_benchmark_<ts>/`: `results.json`, `summary.csv`,
`results.md` (bare-vs-harness), and the two `predictions_*.jsonl`. These are generated
artifacts (git-ignored); the committed ground truth is `data.jsonl`.

## RealBio task layout

Mirrors the existing RealBio public-export tasks (`autofix_benchmark/`,
`protocol_thresholds/`, …): a `data.jsonl` of one ground-truth record per line + a
deterministic `score.py` with a Wilson-CI scorer. Each record:

```json
{"id": "...", "archetype": "...", "label": "positive|negative|hard_negative",
 "target_critic": "...", "expected_code": "...", "clinical": true,
 "governance": "deterministic_advisory",
 "ground_truth": {"should_fire": true, "harmful_if_fires": false},
 "contract": {"design": {...}, "manifest": {...}, "inline_artifacts": {...}}}
```

A prediction record (the harness arm, or any LLM arm in the same schema):

```json
{"id": "...", "arm": "harness", "fired_target": true,
 "target_remediation_kind": "add_covariate", "published_codes": [...]}
```

## bare vs harness

The **harness** arm = registered critics through the real hook. The **bare** arm is a
deterministic LLM-bare *lower bound*: an LLM with no run-contract and no KB, asked "is
this successful run valid?", abstains on every run → recall 0, false-alarm 0. Drop in a
real LLM's predictions (same jsonl schema) to replace the floor. This realizes the
manuscript's bare-vs-harness frame deterministically, without an API call.

## How the number feeds RealBio / RealPharma

This fills the handoff's open gap — *"BioMate's own autofix/self-correction cell = —"*
— with a real self-correction number, in the manuscript's bare-vs-harness frame. It
measures the hard half the `autofix` task cannot (silent validity flaws in succeeded
runs) and reports false-alarm + harmful-remediation as shipping gates. The result
**predicts its own story**: the correctly-designed critics ship at
`deterministic_advisory`, while the one critic with a known fallacy (Table-2 mediator
adjustment) is caught by the harmful-remediation hard gate — the generalizability
claim, *measured instead of asserted*.

## What real run-fixtures would strengthen it

The contracts here are synthetic-but-representative (the honest substitute until real
clean-run contracts are wired). It gets materially stronger with:

1. **The 3 live-proved loops as GOLD anchors** — the real survival confounding run
   (HR 0.817→0.806), the ECOG PH violation, the diffab `~cell+dex` batch case — their
   real `survival_qc.json` / `design.json` as fixtures (committee §4.2 label source 1).
2. **Real clean runs as negatives** — successful runs whose correct verdict is "no
   issue", straight from the executor's `_build_design_json` / `_build_results_manifest`
   (requires Phase-0: the contract is empty for ~100% of workflows today).
3. **The injection/adversarial set** — output files carrying prompt-injection payloads,
   scored on verdict-flip rate (hard 100% bar) — once the LLM critic exists.
4. **≥50 positives and ≥50 clean per archetype** for tighter precision CIs (the current
   `--n 20` gives ~±0.1 bounds; the scorer already reports the Wilson interval).
5. **A real LLM bare arm + an LLM+KB-retrieval arm** to complete the three-way
   bare-vs-harness comparison (§4.5).
