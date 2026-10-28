# First real-model harness evaluation via OpenRouter

Date: 2026-10-09 America/Chicago. Authorized by the user to use OpenRouter before the SSH/local endpoint.

## What actually ran

- Hosted `qwen/qwen3.5-9b`, explicitly routed to DeepInfra through OpenRouter after the initial unrestricted route stalled.
- Actual pinned Hermes tool registry, BioMate's read-only fixture adapter and a small evaluation conversation driver. **This is not the full Hermes AIAgent runtime.**
- Three synthetic task contexts: all-method comparison, two inhibitors × three targets, and six peptide candidates × two property tools.
- Real model tool calls and validator feedback. No client data, real scientific tool execution, training or production deployment.

The model is a hosted model identifier, not BioMate's trained checkpoint. This experiment cannot establish on-premise performance or compare trained weights.

## Paired schema experiment

Both arms used the same model, requested provider, synthetic data, system instructions, temperature 0, eight-turn cap, 5,000-token output cap and 60-second wall-time request limit. The minimal arm used generic step objects/descriptions. The guided arm supplied explicit step fields, named dimension objects with enumerated values, and tool prerequisites. The changed schema and descriptions are one combined intervention; this does not isolate their separate effects.

| Case | Minimal schema: valid plan / results retrieved | Guided schema: valid plan / results retrieved | Original final report |
|---|---|---|---|
| Compare all methods | No; exhausted eight turns | Yes; validation succeeded on first attempt | Guided report request timed out |
| Two inhibitors × three targets | Yes; recovered after an early results request | Yes | Both report requests timed out |
| Peptide shortlist | No; exhausted eight turns | No completed validation response within deadline | No report |

Thus completed plan/result stages were **1/3 versus 2/3**; full original conversation completion was **0/3 in both arms**. These are three diagnostic examples, not a statistically established accuracy improvement or a BioMate production baseline.

Observed minimal-schema failure: the model repeatedly encoded `dimensions` as arrays rather than named objects. The validator rejected missing or malformed coverage. The guided schema made the required shape explicit. This is actionable harness/interface work before deciding that model training is necessary.

## Bounded follow-ups

Follow-ups preserve the original failed records and change conditions explicitly:

- A separate report call with no tools, a 1,800-token cap and a 450-word instruction produced the tool-comparison report. This is a resumed phase, not success of the original uninterrupted run.
- Review found correct fixture scores and recommendation but an irrelevant peptide-shortlist limitation in the method-comparison answer, plus wording that described a validated plan as executed before later denying real execution. The report is **not accepted as product-quality output**.
- A 60-second separate inhibitor–target report attempt also timed out. A case-specific follow-up with a 120-second limit is recorded separately.
- The peptide guided-plan follow-up increased the request limit to 120 seconds and used an explicit short report phase. Its model-generated 12-case plan validated and fixture results were retrieved. This must not be folded into the equal-budget schema comparison above.

The bounded peptide follow-up completed in **five model requests / 156.18 seconds**, with all mechanical gates passing. Its report correctly includes six candidates, twelve scores, totals 3/7/11/15/19/23 and the expected five selected IDs. It clearly labels fixture replay and explains why candidate six is excluded. It lists artifact references for the five selected candidates but omits the excluded candidate's two artifact references; complete report provenance still needs improvement. This is a successful synthetic planning-to-report exercise with a reporting limitation, not scientific acceptance.

The 120-second inhibitor report follow-up completed, retained all six rows/scores and labeled synthetic data, but invented an unrequested top-five shortlist and a cross-target sum policy. Inspection found an adapter defect: its result payload supplied peptide selection guidance to every case. That is harness context contamination; it must not be labeled solely a model defect.

The adapter now supplies separate selection policies: compare methods; compare both inhibitors for each target without excluding pairs; or shortlist five peptides. A scoped-report follow-up retains the exact observed numeric rows and source references, replaces the incorrect policy, and omits unrelated conversation instructions. This changes both policy and context construction, so it is a combined correction rather than a pure prompt-wording ablation.

**Scoped-report outcome:** the same 9B model completed the inhibitor report without a top-five shortlist or invented sum policy. It retains all six scores/references and compares both inhibitors separately for each target. The display is a six-row comparison rather than a literal 2×3 table. Wording that the workflow “processed” the dataset still needs tightening because only fixture replay occurred, despite explicit synthetic/no-real-execution statements elsewhere.

The peptide fixture tool supplied the recommended IDs; the report therefore tests faithful presentation and arithmetic, not independent discovery of a scientifically optimal shortlist. No learned-skill system or weight update was used in these corrections.

## Request handling lessons

The first unrestricted provider call stalled while reading a chunked response. The socket timeout did not provide an absolute request deadline; it was interrupted and never counted as a completed evaluation. The driver now applies a wall-clock alarm as well as a socket timeout. A wall-time failure establishes a budget violation, not inability to reason or a measured local inference speed.

Every report request remains bounded. Failed or interrupted requests may incur provider cost without returning usage; completed-response usage is not a complete billing total.

## Reproduction and artifacts

- [Conversation runner](../evaluation/local_trial/harness_reuse/run_openrouter_fixture_eval.py)
- [Separate report runner](../evaluation/local_trial/harness_reuse/finish_fixture_report.py)
- [Exact system prompt and tool-schema variants](../evaluation/local_trial/harness_reuse/results/20261009_evaluation_prompt_and_schemas.json)
- [Minimal-schema summary](../evaluation/local_trial/harness_reuse/results/20261009_qwen35_9b_deepinfra/summary.json)
- [Guided-schema summary](../evaluation/local_trial/harness_reuse/results/20261009_qwen35_9b_guided/summary.json)
- [First comparison report](../evaluation/local_trial/harness_reuse/results/20261009_qwen35_9b_guided/compare_all_applicable_tools_report_phase.md)
- [Peptide planning-to-report trace](../evaluation/local_trial/harness_reuse/results/20261009_qwen35_9b_peptide_bounded/peptide_shortlist_from_prior_run.json) and [report](../evaluation/local_trial/harness_reuse/results/20261009_qwen35_9b_peptide_bounded/peptide_shortlist_from_prior_run.md)
- [Inhibitor report with the observed policy error](../evaluation/local_trial/harness_reuse/results/20261009_qwen35_9b_guided/two_inhibitors_three_targets_report_phase_v2.md)
- [Corrected scoped inhibitor report](../evaluation/local_trial/harness_reuse/results/20261009_qwen35_9b_guided/two_inhibitors_three_targets_report_scoped.md) and [exact report input/output](../evaluation/local_trial/harness_reuse/results/20261009_qwen35_9b_guided/two_inhibitors_three_targets_report_scoped.json)

Keys are read from `OPENROUTER_API_KEY`, never embedded in code or artifacts. Source hashes are checked before importing the upstream registry. Raw conversation files retain tool arguments, observations, finish reasons and returned usage. The registry component regression suite still passes **30/30** after these additions.

## Implications for the client trial

1. Supply precise tool schemas and stage-specific procedures; do not rely on one broad instruction to enforce the workflow.
2. Keep deterministic coverage and graph validation outside the LLM. It prevented incomplete work from being treated as success.
3. Use case-specific report context and check claims against actual execution state. A complete answer can still contain cross-task contamination or contradictory claims.
4. Consider deterministic expansion of validated case axes to avoid making the model repeatedly serialize large, repetitive graphs. Evaluate this separately; this experiment still required explicit per-case steps.
5. Measure the same tasks on the actual local checkpoint/endpoint before training decisions. Hosted timeout behavior cannot establish local hardware requirements.
6. Continue the product serializer/status/scorer repairs. None of these hosted fixture results repairs the nine earlier product-boundary failures.
