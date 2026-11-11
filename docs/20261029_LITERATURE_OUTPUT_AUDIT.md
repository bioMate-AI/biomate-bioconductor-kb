# Literature extraction and output audit — 29 October 2026

## Assessment

The extraction job completed, and the downloaded merged KB matches its recorded SHA-256. Its outputs are a source-linked candidate collection, not a validated set of design rules. Quotation fidelity, full-entry correctness, incremental coverage and eligibility for a model intervention are separate questions. The current output does not establish that 1,211 strict entries are valid rules or novel additions to existing public knowledge bases.

## Evidence and scope

The audit uses the immutable `k2pilot7_20261029` output, its archived extraction/merge code, the pre-existing raw and strict CSV samples, and the stored full-text corpus. Input hashes are in `20261029_literature_audit/input_manifest.json`; the merged KB hash independently matches `b328017025eaf1d050f82748acdc7c3b283bc67bd5306ca7457122297d7a3d40`. Original extraction records were not rewritten. Source text and raw KB files remain outside the Git review package.

The fixed samples were drawn by the original pipeline, stratified by topic and evidence tier. Reviewing their entries is not a new independent sample from the unmerged emission population. The old merge chose representatives without preserving scope or all member records, so these samples audit that persisted representative output. A whole-population precision claim would additionally require the correct stratum weights and a reconciled sampling frame. No new confidence intervals or scientific aggregations were run on the laptop.

These are AI-assisted source-context judgments, not independent human adjudication. Stored text supports checking what a source says; it does not independently establish the truth of the source's scientific claim. Primary studies cited only through reviews or introductory background need separate inspection before a model intervention.

## Reproducibility and pipeline findings

- Terminal logs show extraction, pre-existing-KB mapping, merge and measurement returned zero. Counts refer to cumulative resumed work: 6,144 verified emissions, 5,969 unique IDs, 5,196 merged representatives from 237 papers and 1,211 strict representatives. These denominators are not interchangeable.
- The archived merge grouped on property, substructure class and direction, followed by lexical similarity. It did not require matching scaffold, assay, target or conditions. A representative can therefore conceal narrower or different member scopes. The implemented scope-preserving revision is prospective; it has not regenerated this output.
- `verify_rule` checks schema, quote occurrence and numerical occurrence. It does not establish that an effect belongs to the reported compound, endpoint or comparison.
- The strict filter adds model entailment, confidence and keyword checks. Its affinity keywords include inhibition, activity and selectivity; this allows functional outcomes to be mistaken for affinity. Peptide terms can admit linear peptides and receptor statements. No strict-filter pass demonstrates intervention eligibility.
- Article type does not establish evidence tier: introductions to research articles can summarise prior work. A T1 assignment must follow the quoted claim's origin.
- Zero author/year benchmark flags do not establish leakage clearance. Source identifiers, compounds, scaffolds and targets still require explicit exclusions.

## Source-grounded failure examples

| Record | Observed problem | Consequence |
|---|---|---|
| K2-76649530902f | The source says removal of terminal polar groups reduces their adverse effect on permeability; the record labels permeability as decreasing. | Direction reversed; reject the original directional rule. |
| K2-d2e32c9e1521 | Source reports cellular TMPRSS2 inhibition for named compounds; record classifies it as binding affinity. | Retain as a compound-specific functional observation only after endpoint correction. |
| K2-fc5211ae1ecd | An introductory statement about a prior gap in D-PD-1 binders is labelled T1; the same article goes on to report such binders. | Background and temporal scope are wrong for a current factual or causal prior. |
| K2-4c761c0659ae | Source reports C-terminal steric effects on cyclization conditions; record labels proteolytic stability. | Recover a scoped reaction observation, not a stability reward. |
| K2-3776fc3b71b8 | Receptor/complex solvent-accessible surface trajectories are labelled solubility. | Wrong entity and endpoint; exclude as a peptide solubility rule. |
| K2-6dde35922ebc | A designed symmetric macrocycle complex has reported affinity, but no contrast isolates symmetry as an enhancing cause. | Do not turn a successful design example into a directional symmetry rule. |

The row-level files retain both supported descriptive content and full-entry failures. A proposed repair does not make the original record pass.

## What may add value beyond existing databases

The promising additional layer is conditional evidence: which modification was tested, on what scaffold, against which comparator, in which assay, with what trade-off or failure. This differs from merely adding another structure/value row. However, novelty relative to surveyed databases is not yet quantified.

The archived `kb_before.py` maps admitted entries from local `experience_kb`, `target_kb` and `medchem_kb` modules into keyword coverage cells. It does not compare the new statements against every surveyed resource. The future import-overlap fields described in the registration are not demonstrated by this pilot's measurement object. A statement absent from our local notes may already exist in a public database or its cited source.

A defensible incremental-coverage study should freeze the imported database snapshots and classify each audited candidate as: duplicate measurement; additional contextual evidence for an existing compound; distinct conditional relationship; review/background restatement; or unresolved. Match DOI/source, compound identity and assay/value for measurements, and scope/comparator/endpoint for relationships. Keep measurement and relationship counts separate.

## Candidates worth recovering for the method

- **Tyrosine-selective SuFEx cyclization (K2-d590a3f68dcd):** source context identifies a particular precursor design, reactive group and buffer conditions. This is a conditional synthesis candidate requiring exact substrate/action mapping, not a global permeability or binding prior.
- **Linear/macrocyclic matched pairs (K2-124d856a78cc):** source context identifies series 1/5, a particular ring disconnection and measured lipophilicity changes. Preserve the matched-pair scope and measured endpoints; do not generalise to all cyclic peptides. The record's separate effect-size annotation needs rechecking.
- **C-terminal steric effects (K2-4c761c0659ae):** the source compares specific residues under a particular closure chemistry. Recover the tested conditional reaction relation after correcting its endpoint.

None is admitted by this audit as a universal numerical reward. For the first knowledge-conditioned method experiment, each accepted record needs source-qualified scope, an implementable applicability predicate, an exact chemical parent/action mapping and leakage clearance. The model intervention is prioritising applicable parents or edits, not inserting prose into an atom-token model. Compare identical model, parent pool, hard rules, seed and oracle budget with knowledge off, applicable knowledge on and inapplicable evidence; log each actual intervention.

## Recommended disposition

Keep the immutable v1 outputs for provenance. Do not scale extraction merely to increase counts. First finish semantic adjudication and versioned corrections, regenerate the scope-preserving merge on authorised remote compute, and distinguish descriptive/context records from executable conditional relationships. Establish increment over imported resources separately. Unresolved records remain retrieval context or quarantined candidates, not sampler weights. The registered acceptance threshold is not changed by this review.

## Completed review records

All 100 entries in each pre-existing sample were reviewed in fixed CSV order: 100 raw-arm records and 100 strict-arm records. The arms can overlap, so this is not a claim of 200 unique rules. Record identity/order was checked against the frozen sample CSVs. No population precision or confidence interval is inferred from these heterogeneous assistant judgments.

- [RAW rows 1–12](20261029_literature_audit/raw_first12_diagnostic.json) and [RAW rows 13–100](20261029_literature_audit/raw_013_100.json).
- [STRICT rows 1–50](20261029_literature_audit/strict_001_050.json) and [STRICT rows 51–100](20261029_literature_audit/strict_051_100.json).
- [Input hashes](20261029_literature_audit/input_manifest.json).

Additional strict-sample findings include an exocyclic-angle direction reversal, RNA degradation classified as peptide proteolytic stability, and cellular adhesion classified as affinity. The parent reviewer independently re-read the source contexts for strict rows 53, 65 and 89 and confirmed the direction error, the scaffold-specific loop-length comparison and the RNA/peptide endpoint mismatch. The useful loop-length example retains coupled sequence changes and its named influenza-HA series; it is not a general shorter-ring penalty.

The registered 0.80 acceptance criterion has not been declared passed or failed on the basis of a new numerical summary here. A reconciled, consistently adjudicated precision calculation and the missing recall/coverage qualification remain outstanding. What is established now is that the current strict filter admits material semantic errors and that no blanket promotion of the strict collection to method priors is justified.
