# Why performance is not as expected — consolidated diagnosis

**Date:** 2026-10-21
**Question:** wrong design, or wrong implementation/evaluation?
**Answer:** Not a model-capacity design flaw. It is **(1) a broken/inflated evaluation**, **(2)
an unbuilt execution/composer substrate**, and **(3) training effort aimed at the wrong layer**.
Three independent read-only reviews (design+results, eval-integrity, bottleneck-location)
converged on this with file-level evidence. Capacity/architecture is the *least* supported
explanation — every "bigger/deeper" test lost.

---

## The one-paragraph version

The on-prem model's headline wins are mostly **evaluation artifacts**: the decomposition
"0.36→0.73" was measured on a benchmark emitted by the *same generator* as the training data
(item-disjoint but distribution-identical) and ~85% of it was a 4-class formatting metric;
on real out-of-generator topologies the number is **≈0.016–0.087** (near floor). Meanwhile the
tasks that *do* hit target (routing 0.82–0.93, param 0.56–0.68) are carried by the
**harness/retrieval, not the model** — a 9B+harness (0.815) beats a bare 27B, and the context
dividend scales *inversely* with model size. Where product performance is actually lost is the
**execution substrate**: the LLM plans multi-step correctly (composed_rate 1.00) but the harness
**discards the plan** (`ai_assistant.py:724-728`), runs a sequential loop with **41% of chain
edges broken**, and the real DAG composer is dead code / stranded on another branch. The two RL
stages that would be real capability gains (GRPO, DPO) **were never launched**, and the single
run meant to settle real-transfer (v3) **was never completed**. So the design isn't wrong about
*the model* — it's aimed at the wrong *layer*.

---

## Evidence (three reviews, all file-grounded)

### A. Capacity/architecture is NOT the bottleneck
- `proto_deep` (L4, d512) **< `proto`** (shallow) on annotF1 at matched steps (0.250 vs 0.284); shallow is 8× faster and plateaus higher.
- `proto` tokenizer **≈ trivial stub** backbone (macroF1 0.443 vs 0.465) on the first real leave-study-out run.
- Newer **3.8-27B does not beat 3.5-27B** on any routing cell; 9B→27B lifts bare routing only 0.12→0.24.
- Immune-FM full multi-omic: linear-probe advantage only **+0.054**, causal perturb **below** the condition-mean baseline. Deep perturbation models lose to train-mean (field consensus: "0 of 62,928 comparisons beat all baselines").
- **9B + harness (0.815) beats a bare 27B**; catalog/KB dividend 9B **+63pp** vs frontier **+34pp** → context substitutes for capacity on exactly the product tasks.

### B. The evaluation is broken/inflated (the "wrong eval" hypothesis — substantiated)
- **Decomposition 0.73 is a same-generator in-distribution artifact.** `build_decomp_depgraph.py` emits *both* the SFT rows and `decomposition_v2`; authors already **retracted** it (`20261007_SFT_V3_REAL_RETRAIN.md:14-20`). Real out-of-generator ≈ **0.016/0.087**.
- **~85% of the decomposition "gain" is a 4-class shape-binning metric** (honest Δ +0.033, McNemar p=0.092 — not significant). Gold labels are template placeholders (`"<domain> analysis"`), zero tool content — it never measured tool-DAG identity.
- **Tiny, single-seed evals** (task_decomposition n=30; decomposition_real n=68 skewed 60/5/3; decision n=30) — no reported delta is statistically supported.
- **A degenerate adapter shipped** once (empty loss mask, train_loss 0.0007) and was spun up on an eval box before being caught.
- **The teacher-fidelity judge rewarded a hallucinated wrong workflow as 1.0** — the 0.52/0.54 macro "fidelity" numbers are judge noise.
- CPT eval had **5+7/261 leaked stems**; leak-controlled knowledge gain drops +5.4→+3.8pp.
- **SELF-CORRECTION — this session's own work has the same flaw.** `build_decision_sft.py` (commit `01ad72ae0`) trains on **every** benchmark item with **no held-out split**, and the GRPO reward (`decision_reward.py`) is the **same scorer** the benchmark uses (`decision_benchmark_adapter.score`). Any decision-benchmark score from that model is ceiling-by-construction and will not survive on unseen decisions. n=30 is also non-inferential. **This must be fixed before any decision-SFT/GRPO number is cited.**

### C. The execution/composer substrate is where product performance is lost
- The LLM plans correctly: **composed_rate 1.00, validity 1.00**. The harness then **discards** the `parallel_with`/`depends_on` hints (`ai_assistant.py:724-728` — "full parallel dispatch is Phase 1" = unbuilt).
- Chain exec is a sequential for-loop (`workflow_chain.py:465`); **41% of chain connections broken (56/137); only 5/69 chains fully OK** — the handoff/semantic resolver is the dominant failure.
- The backend DAG composer (`decomposed_dag.py`, `build_dag_plan`, flag `BIOMATE_MULTITASK_DAG_ENABLED`) has **zero live callers**; the real executor (`map_reduce.py`, 11/11 tests) is on a separate branch — a coordination gap, not a missing capability.
- Agentic tools "don't fire" in live chat because of **over-eager intent classification + a thinkingBudget:0 HTTP 400**, proven by isolation tests to be **"NOT the model."**

### D. What the training actually did
- SFT **did not help** model-bound tasks: routing 0.885→0.860, param 0.628→0.612, `must_not_fill` over-filling **worsened** with more training (34→61).
- SFT wins only **in-distribution/format**; **does not transfer** to real topologies.
- **CPT/mid-train hurts routing (−5.3pt)** → declared NO-GO; knowledge bump is modest and non-scaling.
- **GRPO and DPO never launched**; **v3 real-transfer run never completed** (empty results, "awaiting spot capacity"). The decisive numbers are *unrun, not negative*.

---

## Verdict: design vs implementation/eval

- **Not a model-capacity design error.** No evidence a bigger/deeper/newer backbone helps; several results argue the opposite.
- **It IS a design error of *targeting*:** the effort went into training the model, when the measured leverage is in the **substrate** (execute the plan the model already produces) and the **context/KB** (inverse-scaling dividend).
- **It IS an implementation error:** the composer discards the plan, 41% of handoffs break, the real DAG executor is dead/stranded.
- **It IS an evaluation error:** leakage + generator-overlap + coarse metrics + tiny n + a broken judge inflated the headlines; the real-transfer and RL runs that would tell the truth never ran. This *masks* the true location of every other problem.

---

## Corrective plan (prioritized)

**P0 — Clean the evaluation first (nothing is trustworthy until this is done).**
- Standardize on **out-of-generator / leakage-controlled** splits everywhere; cite `decomposition_real`, never the retracted `decomposition_v2`.
- Build a **held-out decision eval disjoint from `build_decision_sft`** (split items; never train on eval); add a **paraphrase-aware** leak guard (the current one is exact-string + public_export-only).
- Require **n, significance, and a null baseline** on every reported delta; retire the hallucination-rewarding fidelity judge.

**P1 — Wire the execution substrate (where product perf is actually lost).**
- Implement parallel fan-out + an aggregate/rank/top-k/select node; **stop discarding** the plan's `parallel_with`/`depends_on`.
- Fix the 41%-broken handoff/semantic resolver; wire the live DAG composer (land `map_reduce.py`; give `build_dag_plan` real callers).
- Fix the intent-classification gating + thinkingBudget:0 that turn agentic tools off.

**P2 — Redirect training to the narrow LLM-bound slice, measured on clean evals only.**
- Feed **context/KB** (biggest, size-robust win) and **SFT on REAL DB gold** for weak-base tasks (findings, param restraint) — not CPT, not depth.
- Run the deferred **GRPO/DPO only after** a clean held-out eval exists and only on **real** topologies.

**P3 — Finish the unrun decisive experiments** (v3 real-transfer) so decisions rest on numbers, not "pending."

**Reframe:** a small on-prem model + harness ≈ frontier + harness on the product tasks. Invest in
substrate + context + real-gold SFT on the LLM-bound slice, cleanly measured — not a bigger backbone.

(Diagnosis only; no code changed. Immune/VCC leakage lives in a separate repo
`/Users/kky/biomate-immune-llm` and was not re-verified here.)
