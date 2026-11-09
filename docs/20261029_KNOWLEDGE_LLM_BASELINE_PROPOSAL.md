# Proposed general-purpose LLM baselines for knowledge-conditioned peptide design

29 October 2026. Design proposal only; no API experiment executed, budget authorised, model snapshot selected or existing registration amended by this document.

## Scientific questions

1. Does the audited knowledge collection improve candidate decisions across Claude, GPT and Gemini compared with each model's knowledge-off condition?
2. Does IH-LM provide an advantage over general-purpose models given equivalent source evidence, candidate opportunities, hard constraints and oracle budgets?

The first contrast supports the utility of the knowledge collection. The second evaluates the specialised method. A result on one contrast does not answer the other.

## Minimal matched design

For one frozen API model snapshot per provider, compare: chemical examples and task only; identical inputs plus applicable audited knowledge; and identical inputs plus a preselected topic/length-matched packet whose applicability conditions do not hold. The applicable and inapplicable packets must be fixed before results; their content and applicability judgments must be verified. The knowledge-off arm retains the same chemical examples and task description. Topic/length matching reduces, but does not eliminate, context-length and attention confounding.

Use a fixed candidate pool for the first decision-level diagnostic, so models rank or choose parent/edit IDs rather than relying on differences in SMILES generation. This is a selection experiment, not a generative result. A subsequent generation comparison can use a shared validated chemical-edit executor or direct structures; these are distinct protocols and must not be pooled. Direct LLM generation is an end-to-end comparator, whereas a shared executor better isolates the decision policy.

Each answer includes candidate/parent ID, a schema-constrained edit or structure, cited evidence IDs and a short applicability justification. External chemical validation determines validity, stereochemistry and hard-rule satisfaction. Claimed rationales are not proof of evidence use; compare actual decisions, source relevance and wrong-scope rejection. Keep all refusals, malformed answers, failed edits, duplicates and invalid structures in proposal/time accounting. Do not provide unlimited silent retries.

Use equal oracle-call budgets under the existing charging convention, identical chemical starting opportunities and identical feedback information per round. Freeze retrieval packets first to isolate reasoning with evidence; provider-specific retrieval and autonomous web browsing are out of scope for the initial test. General-purpose prompting is in-context adaptation, not weight training; distinguish it from IH-LM adapter updates. Prompt tuning must use development tasks and a bounded equal opportunity, never evaluation results.

Report paired within-model knowledge effects and cross-model contrasts, valid/unique novel proposals, train-objective AUC, final held-out scores, scope rejection, evidence attribution, proposal counts, token usage, latency and actual API spend. Use the same experimentally meaningful endpoints across methods. The unresolved held-out/AUC margin issue in the method draft must be fixed prospectively before a confirmatory comparison. Do not resolve the F1 verifier failure by substituting a commercial LLM judge. Evaluate statistical precision before choosing a confirmatory sample size; a small pilot is exploratory.

## Reproducibility and data boundaries

Pin exact model IDs/revisions where available, request parameters, prompts, evidence packet hashes, candidate pools, seeds where supported, request IDs, response timestamps and raw responses. API nondeterminism remains even with fixed settings. Establish available model versions, context limits, pricing and a bounded budget immediately before running; no assumption of API credits is made here. Use approved public-source evidence packets; do not send internal documents or unreviewed patent content to provider APIs.

## Provider documentation consulted

- Claude structured outputs: https://platform.claude.com/docs/en/build-with-claude/structured-outputs
- OpenAI structured outputs: https://developers.openai.com/api/docs/guides/structured-outputs
- Gemini structured outputs: https://ai.google.dev/gemini-api/docs/structured-output

Structured output support helps enforce the response interface; it does not validate molecular chemistry, biological claims or correct application of evidence.
