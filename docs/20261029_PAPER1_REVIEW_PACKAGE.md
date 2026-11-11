# Paper 1 review package — 29 October 2026

**Status: prepared for internal author review; not submitted.** Scientific corrections have been incorporated into the local master. Author metadata, declarations, journal choice and reviewer access remain pending. This index points to existing evidence; it is not a public archival release.

## Manuscript and review record

| Item | File |
|---|---|
| Current master, including Methods and supplementary tables/notes | [Manuscript](20261030_MANUSCRIPT_EVAL_CONTROLS_DRAFT_v2.md) |
| Independent review, retained as a historical finding list | [Scientific and submission review](20261029_PAPER1_SUBMISSION_REVIEW.md) |
| Resolution of seven scientific findings and numerical provenance | [Takeover and resolution record](20261029_CODEX_PAPER1_TAKEOVER.md) |
| Earlier number-to-file registry and outstanding work | [Progress record](20261031_PROGRESS_PAPER1.md) |
| Citation-verification record | [Citation audit](20261031_PAPER1_CITATION_VERIFICATION.md) |
| Editable cover-letter draft; declarations pending | [Cover letter](20261029_PAPER1_COVER_LETTER_DRAFT.md) |

The local master supersedes the older long draft for this package. The existing Drive copy was not reconciled or overwritten. Dates in pre-existing October 30–31 filenames are identifiers and do not establish registration or execution chronology.

## Main figures and source data

| Figure | Vector file | Preview |
|---|---|---|
| 1 — Evaluation design and transductive limitation | [PDF](figures/paper1_review_20261029/paper1_fig1_design.pdf) | [PNG](figures/paper1_review_20261029/paper1_fig1_design.png) |
| 2 — Seed versus source uncertainty | [PDF](figures/paper1_review_20261029/paper1_fig2_feedback.pdf) | [PNG](figures/paper1_review_20261029/paper1_fig2_feedback.png) |
| 3 — Gate calibration and real-benchmark flags | [PDF](figures/paper1_review_20261029/paper1_fig3_gate.pdf) | [PNG](figures/paper1_review_20261029/paper1_fig3_gate.png) |
| 4 — Exact-potency few-label screening | [PDF](figures/paper1_review_20261029/paper1_fig4_transfer.pdf) | [PNG](figures/paper1_review_20261029/paper1_fig4_transfer.png) |

The parent workstream reports visual inspection of all four earlier renders and the final revised Figures 1 and 3; Figure 2's final change was a descriptive marker label, and Figure 4 was unchanged. Final integrated manuscript pagination and submission-file QA remain separate checks.

- [Plotted numerical values](figures/paper1_review_20261029/plotted_values.json): figure-specific records and confidence intervals.
- [Figure legends](figures/paper1_review_20261029/figure_legends.json): exact renderer legends.
- [Source manifest](figures/paper1_review_20261029/sources.json): input paths, SHA-256 hashes and commit identifiers.
- [Figure generator](../research/guangzhou_all_atom/figures_paper/paper1_review.py): selects frozen records; does not run a new experiment.

| Evidence | Source record |
|---|---|
| Figure 2 source contributions and intervals | [paper1_cluster.json](../research/guangzhou_all_atom/cyclic_llm/paper1_cluster/results/paper1_cluster.json) |
| Permeability yield and candidate-subset ranking tables | [l7_aggregate.json](../research/guangzhou_all_atom/cyclic_llm/loop_retro/results/l7_aggregate.json) |
| Figure 3 calibrated gate, flags, operating characteristics and permutation tests | [gcal_eval.json](../research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/gate_calibration/results/gcal_eval.json) |
| Figure 4 exact-potency learning curves and screening contrasts | [test_summary.json](../research/guangzhou_all_atom/cyclic_llm/ihlm_backbone/pilot4/results/test_summary.json) |
| Historical analysis-I control intervals | [validity_gate_I.json](../research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/results/validity_gate_I.json) |
| Original gate positive controls | [gpc_summary.json](../research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/gate_positive_control/results/gpc_summary.json) |

The original source locations above refer to the full research checkout and are not all included in the isolated review PR. Frozen copies of the three figure inputs are included under `figures/paper1_review_20261029/data/`. These JSON records provide figure source data and selected manuscript evidence. They do not replace the complete reconstruction package, source-library permissions, software environment or accessible registration records.

## Before submission

- [x] Correct transductive-versus-prospective wording, source-share denominator, protocol/interval labels and gate scope; document resolution.
- [x] Assemble four figures, exact legends, plotted data and input provenance.
- [ ] Confirm journal and article type; adapt cover letter and formatting to that destination.
- [ ] Supply author names/order, affiliations, corresponding-author details, contributions, funding/acknowledgements and competing interests. Confirm all authors approve the manuscript and submission.
- [ ] Confirm related manuscripts, preprints and any overlapping submissions; provide required disclosure. No originality/exclusivity declaration has been assumed.
- [ ] Complete the applicable Reporting Summary and any journal-specific forms.
- [ ] Provide a concrete reviewer-access link or accessible supplement for code/data, frozen benchmark lists, registrations/amendments and environment/reconstruction instructions. A public persistent identifier is not yet assigned.
- [ ] Resolve CycPeptMPDB redistribution permission; use permitted identifier/reconstruction materials if measurements cannot be redistributed.
- [ ] Finish citation/claim verification and add appropriate primary dataset/model/software references. Bibliographic identity checks are not full-text claim verification.
- [ ] Export and inspect a combined Word/PDF submission manuscript and separate Supplementary Information as required; validate figure labels, references, links and table pagination.
- [ ] Author/corresponding-author final review, then actual portal submission. No portal submission, email or publication has occurred in this workstream.

Nature's [initial-submission guidance](https://www.nature.com/nature/for-authors/initial-submission) and [formatting guide](https://www.nature.com/nature/for-authors/formatting-guide) informed this checklist. These are a provisional destination-specific reference, not confirmation that Nature has been selected or that the work meets its editorial threshold.

## Reproduce the figures

On an EC2 worker with NumPy and Matplotlib installed, run from the repository root:

```sh
python research/guangzhou_all_atom/figures_paper/paper1_review.py --data docs/figures/paper1_review_20261029/data --out /tmp/paper1-figures
```

Final remote render: SSM `725ddeff-6abc-4095-9813-5dd4c8cb473f`, Success/0. Draft review PR: https://github.com/bioMate-AI/biomate/pull/306.

## Narrative revision — automated discovery motivation

The current title is “A benchmark framework to guide automated cyclic peptide discovery”. The abstract presents the integrated evaluation contribution and measured calibration improvement. The Introduction motivates the framework through the design–make–test–learn cycle and its evaluation challenges. The Discussion proposes a progression to prospective laboratory validation, adaptations to other drug modalities and implications for laboratory decision-making. Broader applicability and improved laboratory discovery performance remain proposed uses, not demonstrated outcomes. Olympus (reference 14; primary publication metadata and abstract checked) provides context for existing experiment-planning benchmarks.

## Public repository — 29 October 2026

The approved initial 19-file figure reproduction package is public at https://github.com/bioMate-AI/cyclic-peptide-benchmark (initial commit e26db5c). It contains the renderer, frozen aggregate inputs, figures, plotted values, legends, reproduction instructions and a file-hash manifest. Source databases and private project history are excluded. The manuscript Code availability statement links to this actively developed repository and identifies additional analysis code and reconstruction workflows as future additions. This is a figure-level release, not a complete end-to-end reproduction package.

## Publication-language review — 29 October 2026

Reviewed the abstract, main text, figure captions, Methods, availability statements and supplementary material for internal workflow language. Removed repository-development promises, compute-allocation decisions, internal analysis identifiers and unrelated workstream history. Rewrote audit-style passages as scientific descriptions. Retained material disclosures about post hoc criteria, transductive normalisation, failed reproducibility checks, code corrections and test-data exposure. This was an editorial review, not a new experiment or comprehensive source verification.
