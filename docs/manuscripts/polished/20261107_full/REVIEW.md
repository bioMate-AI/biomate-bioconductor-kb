# Full-scope manuscript revision

These are expanded author-review preprints, not submission-certified manuscripts. They replace the withdrawn abridged revisions in the adjacent `20261107` folder. Original manuscripts, data and prediction files were not edited. No new paid model experiments were run and no scores were silently recomputed into the papers.

## Source choice and preserved scope

The RealBio working revision integrates the full August-named paper with the October suite-integration and workflow-results drafts. Those drafts make conflicting editorial scope choices: the October 26 version includes channel routing, whereas October 27 separates it. The expanded revision keeps channel routing as a complementary analysis and preserves historical shared DrugDev results in the supplement, without pooling them into the 610-item core. This is a proposed integration for author review, not a claim that a newly discovered authoritative manuscript already had this exact structure.

The DrugDev revision integrates the four-track design manuscript with the later dose/PK experiments and the landscape comparison plan. It restores the broad contribution rather than renaming a two-task experiment as the entire suite.

| Source content | Location in revised RealBio |
|---|---|
| Five native workflow tasks and 610 items | Abstract, Results, Methods Table 5 |
| All eight historical task columns | Supplementary Table S1, with version qualifications |
| Current model comparisons and fine-tuning contrast | Table 1 and routing results |
| Parameter rules and held-out value probe | Table 2 and associated Results |
| Channel routing, seven channels | Table 3 and complementary analysis |
| Five evaluation dimensions | Table 4 and Results |
| All five original comparator benchmark families | Table 6 and Related benchmarks |
| Co-scientist comparison class | Related benchmarks |
| Worked examples and prompt excerpts | Supplement S2 |
| Uncertainty, systems/conditions, error taxonomy | Methods and Supplements S3/S5 |
| Additional instantiated task families | Supplementary Table S3 |

| Source content | Location in revised DrugDev |
|---|---|
| Four tracks | Introduction, Figure 1, Methods |
| B1–B5 stage tasks | Table 4 |
| Eight free-energy series and 264 ligands | Abstract and dedicated Methods |
| Nine archetypes and 30 decision tasks | Table 5 |
| Six score entry points and adapter design | Decision Methods |
| SFT/GRPO export and 22/8 split | Results Table 1 and training Methods |
| Offline validation and composer diagnostics | First two Results subsections |
| Dose and PK comparisons, local variants and oracle | Results Tables 2/3 and detailed Methods |
| Historical ligand-ranking comparison | Dedicated Results subsection |
| Broad external comparison families | Table 6 and Supplementary Table S1 |
| Existing seeds and planned extensions | Supplementary Table S2 |

A separate approximately 7,992-word comprehensive BioMate evaluation-framework manuscript and the drug-development platform paper were located. Their identities differ from these named benchmark manuscripts; they remain unchanged and are not silently merged into either paper.

## Scientific issues requiring resolution

1. **RealBio conditions and provenance.** The inspected catalog runner builds its menu from benchmark reference labels. It is a fixed-catalog selection experiment, not demonstrated unrestricted retrieval. Some stored rows use differing serving paths or catalog variants. Freeze a per-cell manifest before treating the entire table as a uniform matched experiment.
2. **Parameter-layer score.** The reproduced offline 0.843 uses answer-informed allowable fields and a local matcher. It is retained as an exploratory result, with 27 remaining forbidden-field violations, not labeled live production performance. A prospective evaluation with real schemas and the shared scorer remains necessary.
3. **Historical results conflict.** The full RealBio draft's parameter values differ from later semantic-scoring values. Historical error-taxonomy routing counts also differ from the later board: BioMate 182/200 in the taxonomy versus 0.965 in the leaderboard. Both versions are identified rather than silently reconciled. The taxonomy cannot be used to decompose the later score.
4. **Coverage and workflow metrics.** Missing item IDs can disappear from some scoring denominators. Workflow-generation thresholded success, mean recall and the legacy aggregate are different endpoints. Effective denominators, complete predictions and scorer versions must accompany final results.
5. **Dose policy and malformed outputs.** The historical dose leaderboard uses 18 non-null cases; the oracle and structured experiment use 20. The oracle has privileged curve access and is not the full sequential BOIN design or an upper bound. Three label-policy disagreements remain. Missing dose fields may receive no-dose credit under the current implementation. Reconcile the policy and rescore validated raw outputs before a definitive ranking.
6. **PK reference meaning.** The generated concentration formula is amount divided by distribution volume with unit conversion; it does not model absorption, elimination or accumulation. Hand-authored peak-concentration references require analyte, route, formulation, timing and primary-source documentation. Reproducing a score is not physiological validation.
7. **Broader DrugDev ground truth.** Tissue/organ and special-population values remain provisional. ADMET measured labels and rule-of-five calculations should not all be called experimental measurements. The free-energy oracle check and the 30/30 synthesized-gold check establish scorer consistency, not independent predictive validity.
8. **Execution scope.** The composer diagnosis and the complete execution track are retained. Confidence, precision and handoff fire rate are different endpoints; no completed roster-wide biological execution result is inferred.
9. **External comparisons.** The comparison families are restored. Primary pages were checked for BixBench, LAB-Bench, ScienceAgentBench, BioAgent Bench, BiomniBench, TDC, TrialBench and the Merck free-energy collection. The entire approximately 165-entry landscape has not been reverified. Its wider names remain a comparison inventory without imported size/license/performance assertions. Complete bibliographic records and version-specific evidence are still needed for publication.
10. **Author and release details.** Existing author names, affiliations and correspondence are restored. Original RealBio contribution statements are retained, but authors must confirm contributions, funding, licensing and release identifiers. No public archive or DOI is invented. These drafts are not submitted or uploaded.

The narrower audit in the withdrawn folder contains reproducible checks for selected code paths. Its old statements about omitted tracks, missing author information and approval of narrowed scope are superseded by this review. Its technical findings must not be generalized to uninspected tasks or runners.

## Figures and document production

The old full RealBio source references three images absent from its stated image directory. The design is rebuilt; the newer valid routing plot is retained; the parameter plot is rebuilt with its offline qualification. Older quantitative comparisons remain in tables. The original DrugDev dose figures mix incompatible denominators or explicitly superseded token-budget runs. Their scientific comparisons are preserved as version-separated tables; the graphics are not reused as current results. Original manuscript snapshots and available source-image provenance are retained for review.

Editable Markdown is the source for each Word document and MathML-rendered PDF. PREPRINT watermarks distinguish review copies. The build record includes source hashes, scope checks and render outputs. These checks establish content preservation and layout quality, not resolution of the scientific issues above.

## Final verification record

The expanded sources contain 5,398 words (RealBio) and 5,720 words (DrugDev), including tables and supplements. Each Word document renders to 14 pages; each reading PDF contains 16 pages. All rendered pages were visually reviewed, including the historical nine-column table, the decision-archetype table and equations. Table continuations repeat headers. The DrugDev Word file retains 17 editable mathematical objects; PDF equations are rendered with MathML. Both outputs carry PREPRINT watermarks.

Automated checks confirm that the current RealBio table and every numeric row in the historical RealBio table are preserved, the decision-archetype counts sum to 30, abstracts are 174 and 178 words, figures resolve, and all source manuscript hashes remain unchanged. These are editorial and document checks, not new model evaluations. The scientific limitations listed above remain open.

## Reference-guided revision

The two cyclic-peptide PDFs supplied on 7 November were used as editorial and visual references, not as data sources for either benchmark. This revision retains the full benchmark scope and all existing table cells. No experiments, confidence intervals or model scores have been invented.

- Both manuscripts now contain five numbered figures with explanatory captions and in-text citations.
- RealBio: rebuilt the routing comparison to include all 13 matched language-model rows; replaced the F1-only bar chart with precision, recall and F1; added a four-endpoint performance heatmap and resource-routing comparison.
- DrugDev: moved model findings ahead of implementation checks; revised the abstract around measured comparisons; added dose-tier comparison with the privileged oracle separated, the 12-row PK comparison, and nine-archetype task composition.
- Full external comparison families, historical results, additional task sets, numerical tables and methods remain intact. Tables were renumbered where the Results order changed.
- Figures are reproducible from the manuscript tables using `build/scientific_figures.py`; numerical inputs are recorded in `figures/figure_data.json`, with PNG, SVG and vector PDF versions.
- The reference manuscripts' data, author lists, preregistration claims and experimental validation claims were not transferred.

The previously documented scientific limitations remain unresolved: reference-policy and dose-scorer reconciliation, PK reference provenance, complete run manifests, coverage-sensitive scoring and prospective execution validation. This is an editorial and visualization revision, not an experimental replication or certification of submission readiness.
