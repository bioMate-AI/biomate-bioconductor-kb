# Committee Audit v4 — TASK DEFINITION & DATA SETTING

**2026-09-22.** gpt-5.6 + gemini-3.8-flash + Claude, briefed with the 2026-09-21 finding that the
removal-eval gold was broken (0.27 = metric artifact), corrected to tool-agnostic gold (→ ~0.5), and
mid-training measured as a wash. **Both external members converged unanimously.** Raw reviews:
`committee_reviews/audit_v4_{openai,gemini}.md`.

## Verdict (unanimous)
**The corrected benchmark still does not measure out-of-catalog composition — it measures
query-paraphrase.** Because the gold steps are derived from the query and the judge scores semantic
step-*recall* only, a model that restates the query as standard analysis headers scores ~0.5 without
selecting a substitute tool, checking dataflow types, parameterizing, or executing anything. Therefore
**both the SFT comparison AND the mid-training "wash" are uninterpretable** as capability claims.
v3's causal story ("mid-training was the missing ingredient") is **not supported**; the new "~0.5"
is **not** validated out-of-catalog ability.

## The single biggest validity threat (both members, verbatim-aligned)
> The eval conflates **restating analytical goals from the query** with **composing a grounded,
> executable substitute workflow.** Gold-from-query + recall-only judge ⇒ inflated, uninterpretable.

## Per-dimension findings

**TASK DEFINITION (P0).** "Remove one *retrieved* workflow, reconstruct its plan" is
leave-one-retrieved-workflow-out, not true out-of-catalog — the removed workflow (or paraphrases) may
sit in mid-train/SFT/tool-docs/pretraining. Retrieval and planning are confounded (family-holdout
recall 0.40 → 6–10 distractors). `RUN_CODE` is a loophole (generic "I'll run a script to normalize"
gets credit). Output isn't operational: no tool choice, typed dataflow, params, contrasts, or
execution required. **Fix:** make the primary task an **executable, candidate-grounded workflow DAG**
with typed nodes (TOOL_INVOCATION / GENERATE_CODE), and split into 4 classes —
substitution / composition / code-fallback / infeasibility — scored separately.

**METRIC (P0).** LLM-judged fraction-of-steps-covered is recall-only: rewards verbosity/boilerplate
(a generic QC→filter→norm→model→test→export template hits 4–5/6 of any gold), no precision, **no
penalty for bioinformatic nonsense** (e.g. log/CPM-normalize before a raw-count model like
DESeq2/edgeR; Combat-seq on normalized data; unstranded tool on stranded protocol), no grounding/exec
gate, single-judge variance. Micro favors full_mix +0.01, macro favors sft-only −0.01, nonzero-frac
tied → no stable conclusion. **Fix:** multi-axis scorecard with **hard gates** (semantic coverage
can't compensate for ungrounded/non-executable); primary = end-to-end **pass@1** (schema-valid →
constraints satisfied → grounded in candidates → typed dataflow OK → dry-run/fixture executes →
outputs assert). Add a **negative-constraint adversarial judge** (−0.25 per fatal bioinformatic
violation). **Validate the judge**: 2 blinded bioinformaticians on ≥30 cases, Cohen's κ / Krippendorff
≥0.75; and **degenerate baselines must fail** — a null-echo (query→numbered steps) and a
generic-template model must score <0.15 (if >0.35, the metric is uncalibrated).

**DATA SETTING — eval (P0/P1).** Gold-from-query = structural circularity (CRITICAL). Transcriptomics
55% (44/80) → aggregate is a transcriptomics score, can't back 36-domain claims. **n=80 is
underpowered** — 95% CI on the delta ≈ ±0.055 (σ≈0.25); detecting Δ0.01 needs ~3,000 paired cases,
Δ0.05 needs **N≥220 stratified**; and clustering by workflow-family lowers effective n further; "no
sig diff" ≠ equivalence. No difficulty strata (1:1 drop-ins mixed with multi-tool decompositions).
**Fix:** independent expert gold **blinded to query wording and the removed workflow**; frozen split by
workflow-identity / family / paraphrase-cluster / source / time **before** corpus assembly; stratify
across ~5 super-domains (transcriptomics ≤25%); ≥220 cases; 3 difficulty tiers (direct-replace /
composite-expansion / pure-synthesis); include negative & impossible cases (else abstention is
untestable). Use paired **family-clustered bootstrap** + a pre-registered smallest-meaningful-effect
equivalence test.

**DATA SETTING — train / the mid-training wash (P1).** The result is a **null under one recipe, not
evidence of equivalence.** Four explanations remain undistinguished, and both members confirm
under-dosing: **800×seq1024×batch16 ≈ 13M token-presentations; with 50–75% replay the model saw only
~3–6M domain tokens (<0.15 epoch)**, and seq-1024 truncates whole pipelines/tool-manuals. Plus the
eval may be insensitive to domain knowledge at all. **Decide it cheaply before any more mid-training:**
(1) a **domain-knowledge probe** (≥1,000 tool-I/O-contract / rare-param / ontology facts absent from
the base) measured base-vs-midtrained — if Δ≈0 the corpus wasn't absorbed (dose/seq/arch); (2)
**pre-SFT vs post-SFT** eval of each checkpoint (was knowledge never learned, or overwritten by SFT?);
(3) then a matched-compute **dose × content sweep** (seq→4096, 0→3 epochs, tool-text vs code vs
composition-traces).

**THE CORRECT LEVER (both members, strong):** attack composition in **SFT, not CPT** — inject
**tool-dropout counterfactuals**: for ~30% of the 18,597 multi-step SFT examples, drop the gold tool
from context and supervise the substitute path (secondary tools or a bounded RUN_CODE wrapper). This
aligns SFT with the out-of-catalog distribution directly instead of hoping 13M next-token tokens teach
graph substitution.

## Claude's view (concurring, + sequencing)
I agree on all P0s; I flagged the query-circularity risk in the brief and both members confirm it is
*the* issue. Crucially, **the top two validations are nearly free and should run before building
anything**: the **query-only baseline** (hide all candidates) and the **null-echo baseline**. If
either scores near ~0.5, the current number is confirmed inflated and we stop citing it immediately —
that's a one-hour, no-GPU check that gates all downstream work. Likewise the **pre/post-SFT
domain-knowledge probe** is the decisive cheap test for the mid-training wash. Do the cheap
falsifications first; only then invest in the executable-DAG benchmark rebuild and the SFT
tool-dropout intervention.

## Highest-priority actions (ranked)
1. **P0 — Falsify the current metric now (no GPU):** run query-only + null-echo + generic-template
   baselines on the fixed gold. Expect ~0.5; if so, stop treating ~0.5 as capability. (~1h)
2. **P0 — Rebuild the benchmark:** executable candidate-grounded DAG task; multi-axis + hard-gate +
   negative-constraint metric; independent blinded expert gold; frozen, leakage-controlled,
   domain-stratified, difficulty-tiered, ≥220 cases with impossible/negative cases; judge κ≥0.75.
3. **P1 — Separate retrieval / planning / knowledge:** query-only, oracle-candidate, retrieved,
   shuffled-candidate ablations → attribute failures.
4. **P1 — Decide mid-training on evidence:** domain-knowledge probe + pre/post-SFT + matched-compute
   dose×content sweep (seq-4096). Do NOT run another full pass first.
5. **P1 — Shift the lever to SFT tool-dropout counterfactuals** for out-of-catalog composition.

## Bottom line
The session's *benchmark fix was correct and necessary* (the 0.27 artifact is dead), but it exposed a
deeper truth: **this task/metric can't yet measure the capability we care about.** The right next
investment is **benchmark reconstruction + cheap falsification**, not more training tokens.
