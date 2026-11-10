# Prospective mined-knowledge interface for the method — 2026-10-29

**Prospective protocol with a conditional-parent code prototype; not a validated scientific result.** This specifies how mined literature can influence the molecular generator without converting every quote into an unconditional numeric prior. It extends the [real hybrid integration](20261029_REAL_HYBRID_INTEGRATION.md); that implementation now includes a conditional-parent adapter and synthetic tests alongside chemical retrieval, hard constraints and real-model preference-update code. Remote integration QA is pending. A qualified frozen real-evidence catalogue and measured knowledge benefit remain absent; trained natural-language knowledge conditioning is not implemented.

The generator is ChemFM with an atom-level vocabulary. A literature paragraph or an untrained control token does not become usable knowledge merely by being concatenated to its input. The first proposed interface therefore applies mined evidence to **conditional parent retrieval and proposal planning**, then passes ordinary chemical prefixes to ChemFM. A separate text-capable backbone or trained text-to-chemical adapter would require its own implementation and validation.

## 1. Evidence objects and permitted actions

A frozen evidence object must carry the following fields. This is a proposed schema, not a claim that all existing records provide them.

| Field | Required content |
| --- | --- |
| Identity | Stable evidence ID; upstream K/K2 rule ID; extraction run, code revision and model revision |
| Source | DOI/PMCID, public source URL, source-text SHA-256, exact quote and offsets, access date |
| Scientific scope | Property, assay and units; scaffold/closure family; position or local motif where relevant; solvent/conformation condition; target if applicable; observed versus computed endpoint |
| Claim | Scoped statement, direction or conditional effect, known opposing observations, original evidence tier and reviewed statement-provenance tier |
| Lineage | All source IDs before merging; evidence-family ID; related/matched compound IDs and public structural provenance, when available |
| Quality | Exact-quote result, raw/strict-arm membership, proxy-entailment result, semantic-review status, reviewer type, unresolved flags |
| Leakage | Source-group/family mapping, publication and dataset overlap, scaffold/compound overlap, held-out target/accession flags |
| Permission | `quarantined`, `retrieval_context`, `conditional_proposal`, or `numeric_prior`; allowed action plus prohibited extrapolations |

Permissions are separate from tiers. A T1 exact quote may still be unsuitable for an action. `conditional_proposal` requires an explicit applicability predicate and a validated molecule-level action implementation. `numeric_prior` requires reviewed direction/feature/scope and pinned eligibility; this protocol does not grant it.

Concrete example: `LIT-NME-004` supports testing a specific asparagine-amide intervention in its reported scaffold, with a permeability gain and a binding loss. Its action is not “add methyl groups anywhere.” `LIT-IMHB-001` motivates preserving or shielding backbone NH through conformation, not removing every donor. `LIT-HBD-002` can motivate a labelled HBD-reduction hypothesis; an N/O-token proxy must remain explicitly unvalidated. See the [complete 32-entry review](20261029_KNOWLEDGE_PRIOR_REVIEW.md).

Unknown scope must fail closed for a conditional action. Missing a scaffold/site map means retrieval context only; it does not permit a guessed transformation. If no admissible evidence applies, record `no_applicable_evidence` and use the baseline proposal route. Never count that fallback as knowledge use.

## 2. Molecular interface and audit trail

For each round, the existing train-allowed chemical index produces the same initial candidate-parent pool in every comparison arm. The proposed evidence adapter then:

1. Retrieves frozen evidence objects matching the current target/property and the parent's known scaffold/assay context. Retrieval uses no stop/held-out labels.
2. Applies source-family and compound/scaffold leakage exclusions before ranking. Unknown provenance remains quarantined.
3. Ranks only evidence-qualified parent choices, or proposes one supported local action when a validated action handler exists. It preserves contradictions and binding/solubility tradeoffs. It must not synthesize a new sign from a window or goal statement.
4. Supplies the selected molecular parent/prefix to the ordinary ChemFM generator, with the same prefix fraction and sampling budget as baseline. Existing hard chemistry masks stay identical.
5. Logs selected evidence IDs, source hashes, predicate inputs/result, parent IDs, action type, exclusions, fallback, emitted prefix hash and round seed. The resulting model proposal links back to that record.

The main experiment tests whether **evidence-conditioned proposal choice** helps, rather than whether ChemFM can understand prose. Numeric outcome labels continue to come from the registered training evaluator; literature effect sizes are not substituted into preference labels. Stop/held-out measurements do not enter the retriever or updater. An optional text-capable planner is a future independent arm with a pinned model and structured-action validation, not part of the current implementation.

## 3. Usable evidence now and pending gates

Local evidence inspected for this protocol comprises the gold KB, the 32-entry review, `knowledge_scale/results/import_summary_k2import1.json`, K2/K4 extraction/merge/measurement code, their preregistrations, and the previous takeover worker snapshot. No fresh remote execution occurred for this protocol. The earlier snapshot is not a current completion claim.

| Material | Present evidence | Permitted present use | Gate before method use |
| --- | --- | --- | --- |
| Gold K literature | 107 entries; 32 stored weight-eligible records reviewed; 10 provisional and 22 excluded for the current global token potential | Scoped evidence catalogue and protocol design | Resolve source lineage, scope, leakage and action applicability; no automatic numeric eligibility |
| K2 imports | Local import summary; reported 23 imported files and join controls | Candidate public-source index inputs after provenance checks | Parse/assay harmonization and compound/source-family exclusions; imported rows are not automatically independent evidence |
| K2 scaled extraction | Earlier pilot7 snapshot resumed pilot5's 1,280 passages/2,624 verified rows; 730 were entailment NO; extraction was still running | Quarantined raw evidence only; inspect and design review samples | Terminal successful stage status; preserve raw/strict separation; independent semantic review and frozen accepted subset |
| K3 structure layer | Library and target cards, but independent audit found linker-ring and chemical-annotation errors | Context with explicit quality flags | Reviewed filtering/correction, deduplication and recomputed hashes; no contaminated ring prior |
| K4 patent extraction | Earlier ext3 snapshot: 3,506 passages, 769 verified items; no terminal/postprocessing result in that snapshot | Quarantined separate patent tier; no method reward or public export | Finish deterministic/structure checks, independent semantic audit and lineage/overlap review; separate prospective inclusion decision |

K2's original gate remains: raw exact-quote-match rate at least 40%, judged precision at least 0.80 on a 100-rule sample, and projected coverage at least 60% for recommending scale-up; recall includes its actual denominator. A5/A5.1 preserve separate RAW and STRICT arms with the same precision threshold. STRICT requires entailment YES, confidence at least 0.7, relevance/property terms and eligible SAR directions. These lexical/model checks do not replace semantic review. Applicable per-topic reporting remains required. Passing the extraction gate does not automatically authorize numeric priors or full-scale spend.

K4's scale-up recommendation requires precision at least 0.80 with Wilson interval, structure parse success at least 0.60 among example compounds with a structure string, and at least 20 patents contributing verified examples. The extracting stream's self-audit is not independent; the coordinator must redraw and judge. No patent content is included in the initial knowledge-on arm.

Implementation discrepancies must be reconciled before reporting these gates: current `measure.py::recall_vs_gold` uses same-paper text/quote similarity without the original property/substructure matching requirement. Current merge conflict detection operates at property/substructure cell level rather than a fully defined scope key, and representative selection can conceal member-specific conditions. Retain raw members and report this distinction; do not label these outputs as the exact preregistered metric without a prospective correction or explicit amendment.

## 4. Freeze and leakage controls

Before any comparison, create an immutable **study manifest** binding: accepted evidence IDs and permissions; source-text and raw-record hashes; review table; merge/filter/schema code; molecule mappings; train/stop/held-out membership; retrieval corpus/index; backbone/adapter/tokenizer; evaluator configs; action handlers; sampling budgets/seeds and output schema. Hash the entire manifest and include its hash in every round and checkpoint. No source text or acceptance decisions may change within a run.

Use `track_e/source_groups_v2.json` as the study membership authority. K2's first-author/year overlap flag is only a warning heuristic, not leakage clearance. Join DOI/PMCID and known aliases to full source families; exclude stop/held-out families before building the knowledge index. Exclude compounds and near-duplicate scaffold families according to the registered chemical split. Keep article duplicates, review restatements, and multiple extractions from one experiment in the same evidence family. For target-held-out experiments, remove matching accessions, complexes and derived cards before retrieval or computing any aggregate prior.

Queries may use the task specification and train-allowed chemical features. They may not use held-out assay values, stop-set residuals or evaluation feedback. Store denied and ambiguous records in a separate quarantine index that is never queried by the experiment. A legitimate empty result is preferable to silently relaxing the split.

## 5. Prospective comparisons and acceptance

Freeze three arms before execution; this proposal does not authorize additional compute:

- **Knowledge off:** current hard-rule hybrid plus chemical-parent retrieval and preference feedback.
- **Knowledge on:** identical model, updater, chemical pool, prefix fraction, proposal count, seeds and verifier-call budget; only the conditional evidence adapter changes parent/proposal choice.
- **Matched provenance control:** equal-size evidence packages with inapplicable source/scaffold assignments, labelled as a negative control and never promoted to the production KB. The applicability gate should reject these; report fallback and rejection rates. Do not feed false biological claims as trusted priors.

For a clean causal comparison, freeze source knowledge across online rounds; only train-allowed molecular feedback may update as specified by the main hybrid protocol. Report token/time overhead and evidence-adapter compute separately. Pair seeds and report per-seed outcomes rather than pooled-best scores.

Interface acceptance requires reproducible retrieval/predicate decisions; complete evidence-to-proposal trace; zero forbidden-source access in seeded leakage controls; rejection of altered quotes and inapplicable scope; manifest mismatch failure; identical chemistry masks across arms; and a demonstrated change in selected parents/proposals when eligible evidence is enabled. A context that is displayed but cannot change generation is not a successful integration.

Scientific evaluation then reports registered held-out quality, validity, diversity, failures, verifier calls and cost, plus knowledge coverage, fallback rate, applicable-evidence yield, contradictions, and objective tradeoffs. A positive point estimate without uncertainty and the main study's acceptance rules is not a demonstrated benefit. If the accepted catalogue remains empty or predicates never fire, report the knowledge arm as **not instantiated**, not a knowledge-augmentation success.

## 6. Immediate parallel work

The implementation stream can build and test the structured adapter with explicitly synthetic fixtures while the evidence stream independently qualifies public records and the extraction stream finishes already-authorized pilots. The evaluation stream freezes arms and leakage controls before viewing new outcomes. These tasks do not require fabricated eligibility or unconditional priors. The current real-model L0 smoke can validate the hybrid execution path, but cannot establish the proposed knowledge-on interface or its benefit.

Public release remains paused; no internal records or patent examples are exported by this protocol. Full-scale extraction and later study spending remain under their existing approval gates.

## Prospective implementation corrections (same-day follow-up)

The identified K2 metric/merge discrepancies have now been patched in source, without changing active workers or regenerating existing results. `recall_vs_gold` requires same source plus explicit matching property and substructure before the preregistered text/quote similarity can count a match. Gold records lacking a reviewed classification remain in the in-corpus denominator, with recall `null`, an INCONCLUSIVE status and a separately labelled lower bound; no classification is inferred from the extraction being evaluated. `--gold-classifications` accepts an explicit reviewed map when the gold schema lacks those fields.

Merge v2 keeps scope, assay, target, topic and explicit conditions separate, preserves every raw member and source, and marks the representative as display-only. Unknown scope does not establish equivalence. Cross-paper opposite-direction conflicts are now scope-specific, including the case where both directions have the same multi-paper support set; within-paper opposing evidence is retained separately. RAW/STRICT measurement expands preserved raw members rather than silently applying a representative's quality flags to all support. These are versioned prospective semantics; old and new counts must not be presented as directly comparable without an explicit reanalysis.

K2/K4 future-launch drivers now stop on nonzero stage exits, preserve the original failure, write structured terminal status, and avoid success markers for failure. A final output-sync error is also treated as failure; publication retries are best effort, so missing/stale remote state is never sufficient completion evidence. No running pilot was changed.

A focused synthetic regression suite and an isolated CPU-only SSM bundle were prepared; no local tests were run for these corrections. The bundle runs the existing K2 verifier tests plus contract tests for class-constrained recall, missing classifications, source identity, preserved members, scoped conflicts, and shell failure handling with mocked cloud/shutdown commands. Remote validation is pending; no new extraction run is authorized by this patch.

Remote verification completed: SSM command `7a2783e5-ea69-4f09-a4f1-7e345d9854ed` returned Success/0. The isolated Spot CPU run passed **19 tests in 0.09 seconds**, comprising the existing verifier suite and the new recall/merge/failure contracts. Evidence is in `s3://biomate-nextflow-work/cyclic_peptide/allatom/codex_takeover_20261029/k2_contract_qa_v1/` and the locally retrieved `/tmp/codex-k2-contract-results/tests.txt`. The launch-driver tests mock cloud and shutdown commands; no extraction job was launched, and this is not an extraction-quality or model-performance result.
