# Knowledge integration: reconciliation with documented immune surveys

Recorded: 2026-11-08T01:18:31.998268-06:00

Scope: review of our existing documents and the current experiment. This is not a fresh verification of primary publications. Paper-specific descriptions below are attributed to the surveys; quantitative literature claims have not been revalidated here. Peptide-specific knowledge reviews are outside this immune assessment.

## What the documents actually recommend

- 20260730_SURVEY_LITERATURE_KB_PLUS_BIOLOGY_FOUNDATION_MODELS.md (biomate-audit-fix/docs): literature-derived gene/disease embeddings, biomedical KG grounding and small downstream models built on existing representations. Some entries are explicitly marked verify. Its assertive language about knowledge compensating for scarcity is a design thesis, not a demonstrated result for our model.
- 20260820_KNOWLEDGE_AUGMENTED_SINGLECELL_SURVEY.md (same worktree): separates literature embeddings (GenePT/scELMo), training-time structured priors (GeneCompass), graph propagation for unseen perturbations (GEARS), cross-modal translation, and evidence retrieval. It explicitly warns that knowledge can be decorative and requires no-knowledge/linear controls. Statements that every ingredient is battle-tested or that a graph fixes sparse-disease coverage are stronger than the evidence establishes for this system.
- 20260807_SINGLE_CELL_FOUNDATION_MODELING_SURVEY.md (same worktree): describes graph-informed regulatory alignment and mechanistic priors, but also strong simple-baseline results and thin evidence for blind OOD interventional superiority. This document does not support an unconditional knowledge-always-helps claim.
- 20260830_VIRTUAL_CELL_MODELING_SURVEY.md (same worktree): distinguishes learned representations from perturbation simulators and discusses knowledge-guided tokenization and hybrid predictors. It does not equate an extra input channel with all these mechanisms.
- 20261107_1734_CST_IMMUNE_MODEL_SURVEY_AND_RESEARCH_PLAN.md (biomate-review/docs): explicitly requires native input processing, matched tuning/input availability, and factorial specialist / representation / knowledge / both comparisons. KG/RAG traceability is evaluated separately from prediction improvement.

## Mechanism-to-experiment map

| Surveyed mechanism | Intended use in the surveys | What the latest experiment establishes |
|---|---|---|
| Gene-function text embeddings | Supply semantic relationships beyond measured expression | Not tested by the 768-dimensional channel |
| Structured training priors | Shape gene representations, attention or learning objectives | No matched training-with/without-prior comparison in the latest diagnostic |
| GO/PPI/regulatory graph propagation | Transfer across scarce or unseen genes/perturbations | Not tested by stimulation classification or pathway means |
| Knowledge-guided tokenization | Organize representation learning around biological structure | Pathway-initialized prototype components remain in the checkpoint even with the auxiliary channel off |
| RNA-derived pathway/TF channel | Express pathway/regulon activity summaries | Tested as an inference-time toggle within one checkpoint |
| RAG and evidence reasoning | Improve support, traceability and factual grounding | Not evaluated by classifier AUPRC |

The channel-off arm is therefore NOT a knowledge-free model. Knowledge can remain in prototype initialization, trained weights and other training objectives. Toggling the input cannot estimate the total benefit of knowledge-informed training.

## What our result means

After CP10k correction and approximate saved-corpus scaling, frozen RNA-only AUPRC at C=1 was 0.7092 and RNA-plus-derived-knowledge was 0.6847; raw RNA was 0.8770. This is a small negative effect of this reconstructed auxiliary input at inference on one exploratory stimulation endpoint. It is not a contradiction of every knowledge-augmented method in the surveys. Exact historical scaler/basis identity, dataset overlap and independent validation remain unresolved.

The code computes each auxiliary feature as a mean over pathway/TF-set member expression. Gene-set membership does encode curated information, but this is not a signed regulatory model, graph message passing, or literature-derived semantic embedding. Selecting sets by HVG coverage also does not establish relevance to the stimulation endpoint.

## Revised experimental priorities

1. Document implementation coverage against each surveyed mechanism. Distinguish active forward-path inputs, initialization priors, training objectives, unused assets and reasoning/RAG components. Do not infer absence from this single channel test.
2. Finish an explicit inference bundle with source hashes, gene order, scaler provenance and exact saved knowledge membership. Validate prediction parity.
3. Add a cheap direct-knowledge baseline: pathway/TF features alone and concatenated with raw RNA, with matched training labels and inner-validation tuning. This tests whether the summary features help the endpoint before blaming the neural integration.
4. Separate biological content from channel size: real gene sets versus size/coverage-matched shuffled sets, with prespecified seeds and null constructions. Graph priors additionally need degree-aware controls.
5. For the relevant architecture, train matched knowledge/no-knowledge arms with identical data, objectives apart from the specified prior, tuning budgets and compute. Account for knowledge-derived initialization; call an arm knowledge-free only if all claimed knowledge paths are removed or explicitly held constant as background.
6. Evaluate where the surveys predict benefit: unseen-gene perturbations, low-data cross-study transfer and appropriate regulatory/cross-modal endpoints. Keep current stimulation results as one task, not the sole gate for the whole knowledge strategy.
7. Verify primary references and specific ablations before adopting their quantitative claims or asserting that an implementation reproduces a published mechanism.

Conclusion: retain knowledge integration as a research direction, but improve its implementation and experimental definition. The existing surveys already require this distinction. No new experiments or primary-literature verification are claimed by this document review.
