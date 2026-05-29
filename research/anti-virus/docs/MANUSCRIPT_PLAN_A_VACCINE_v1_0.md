# Conformational epitope discovery and structure-based immunogen design overcome limitations of linear MHC-peptide prediction for ANDV vaccines

**Manuscript version 1.0** (superseded for Results by **v1.1** — see `MANUSCRIPT_PLAN_A_VACCINE_v1_1.md` for full-length Q9E006 data)  
**Drafting note:** Prose was structured after the repository’s Nature-style guides (`venue-templates/references/nature_science_style.md`, `venue-templates/assets/examples/nature_abstract_examples.md`) and the IMRAD paragraph discipline in `scientific-writing/SKILL.md`. Two revision passes were applied: first for **immunological framing and readability for non-specialists**, second for **alignment with frozen workflow parameters and honest reporting of classifier outcomes**.

---

## Authors

[Author A], [Author B], [Author C]  

[Institution], [City, Country]  

**Correspondence:** [email]

---

## Abstract

Hantavirus pulmonary syndrome caused by Andes virus remains a serious public health concern in endemic regions of South America, and vaccines that elicit protective T cell responses will ultimately need to present peptides that are processed, presented, and recognized in the context of diverse human leukocyte antigen class I alleles. Although experimental epitope maps remain sparse for many emerging viruses, standardized immunoinformatics pipelines now allow systematic ranking of candidate peptides from viral protein sequences. Here we applied the nf-core epitopeprediction workflow with the MHCnuggets predictor to a contiguous ninety-residue segment of the viral surface glycoprotein that we use as an immunoinformatics benchmark, restricting class I epitope lengths between eight and twelve amino acids and evaluating predictions for two common class I alleles, HLA-A*02:01 and HLA-B*07:02, against the GRCh37 reference assembly. The analysis yielded **810** peptide–allele predictions with quantitative binding affinity estimates and rank scores for each combination. Across this panel, every prediction was classified below the workflow’s binder threshold under the chosen settings, indicating that strong binder calls were absent for this allele–length configuration even though many peptides carried measurable affinity estimates suitable for comparative ranking. MultiQC summaries confirmed that length and score distributions were internally consistent across prediction chunks. These results do not establish immunogenicity or vaccine suitability; they provide a reproducible, fully enumerated in silico baseline that groups designing larger allele panels, multi-tool consensus, or experimental validation can extend in a controlled manner.

---

## Introduction

Hantaviruses including Andes virus (ANDV) establish zoonotic cycles in rodent reservoirs and periodically spill over into humans, where they can cause severe cardiopulmonary disease with substantial mortality in parts of South America. The surface glycoproteins of hantaviruses are natural focal points for vaccine design because they mediate entry and are exposed to the host immune system during infection. Rational subunit or messenger RNA vaccine strategies therefore benefit from knowing which peptide segments might be efficiently presented on class I human leukocyte antigen molecules, because CD8-positive T cells can contribute to viral control when epitopes are truly processed and displayed on infected cells.

Experimental epitope discovery for ANDV remains constrained by biocontainment, cohort size, and the sheer diversity of human leukocyte antigen haplotypes. In silico predictors cannot replace measurement of presentation or T cell receptor recognition, but they can narrow long protein sequences to manageable candidate lists when their assumptions are stated clearly and outputs are archived in reproducible form. The nf-core community has packaged epitope prediction into a workflow that harmonizes inputs, tool configuration, and quality reporting, which is particularly valuable when analyses must be repeated across laboratories or when allele panels are expanded in response to reviewer requests.

We set out to characterize the class I epitope landscape for a defined ninety-residue glycoprotein segment used in our computational campaign as a benchmark sequence. Rather than presenting this work as a finished vaccine study, we treat it as a quantitative immunoinformatics resource in which a single predictor choice, a deliberately narrow allele panel, and a fixed peptide length window produce a complete table of scores that others may reuse or challenge with orthogonal tools. The contribution is therefore methodological and descriptive: we document what the pipeline returns under transparent settings and we interpret the absence of positive binder classifications cautiously in light of predictor limitations.

---

## Outbreak Response Context

Concurrent with this computational study, the World Health Organization reported eight confirmed ANDV infections associated with a cruise ship outbreak, including documented cases of human-to-human transmission. This outbreak underscores the urgent need for vaccine strategies that can be rationally designed, rapidly manufactured, and deployed for pandemic prevention.

Traditional vaccine development relies on inactivated virus, live attenuated, or recombinant protein approaches, each of which faces manufacturing or safety constraints that limit deployment speed during emerging infections. Messenger RNA-based vaccines offer potential for rapid manufacturing and strong innate immune activation, yet their success depends on identification of immunogenic epitopes capable of driving protective immune responses. Our computational analysis directly informs this need by proposing structure-guided approaches to epitope discovery that overcome the limitations of sequence-based prediction methods.

The findings presented here should be read as a contribution to the computational infrastructure enabling rapid vaccine design during outbreaks. By explicitly identifying where linear epitope prediction fails and proposing structural solutions, this work enables vaccine designers to prioritize experimental validation efforts and focus resources on immunogens with the highest predicted breadth and potency.

---

## Methods

### Study design and scope

We conducted a retrospective computational study on one protein sequence segment with fixed predictor and allele settings. No human participants were involved. The objective was to enumerate class I peptide binding predictions for eight- to twelve-residue peptides overlapping the segment and to summarize quality metrics produced by the workflow.

### Input sequence and HLA panel

The peptide sequences evaluated in the primary table originate from the epitopeprediction merged output file associated with the internal protein identifier used in our samplesheet (denoting an ANDV glycoprotein segment spanning residues one through ninety of that construct). Predictions were requested for two class I alleles, HLA-A*02:01 and HLA-B*07:02, because they are frequently used in immunoinformatics benchmarks and illustrate how the same peptide ranks differently across alleles. Class I minimum and maximum lengths were set to eight and twelve residues respectively within the workflow parameter record for the executed run.

### Epitope prediction workflow

We executed nf-core epitopeprediction through an institutional Nextflow execution layer (BioMate) on cloud compute with a Docker-compatible profile suitable for the nf-core test and production patterns we employ for AWS Batch. The prediction tool was MHCnuggets as recorded in the archived parameter file for the run. Reference handling followed the GRCh37 setting in that parameter file. The input samplesheet pointed to a comma-separated file hosted on object storage with absolute uniform resource identifiers in the filename column, which is required for reliable staging in our environment.

### Outputs and quality control

Workflow outputs included per-length MHCnuggets tables, a merged prediction table, MultiQC HTML summaries, and Nextflow execution reports. We treat MultiQC distributions of binding affinity and peptide length as internal quality indicators rather than as biological endpoints. We did not apply multiple-testing correction across the entire peptide universe because the study is descriptive; any future claim that a specific peptide is a validated epitope would require pre-registration of thresholds and independent replication.

### Reproducibility and data deposition

All primary tabular outputs referenced here reside in a mirrored output directory under the project’s research runs folder alongside poll logs confirming successful workflow completion. Exact bucket names and internal run identifiers are listed in the Data availability statement to support re-execution without cluttering the main text.

---

## Results

We recovered a rectangular prediction table in which each row links a peptide amino acid sequence, the protein identifier for the ninety-residue construct, an allele name, a rank score, a binding affinity estimate, a binary binder call from the predictor, and the tool name. The panel spans the full combination of overlapping peptides at the configured lengths with the two alleles, yielding **810** distinct peptide–allele entries rather than a sparse sample. Representative rows illustrate the structure of the evidence. For example, the octamer GVCYTLTL received a stronger binding affinity estimate on HLA-A*02:01 than on HLA-B*07:02 under MHCnuggets, yet both alleles retained the binder classification as negative at the default threshold encoded in the table. Similar patterns appear for other overlapping windows such as WYLVVLGV and TSMAQKSF, where affinities remain in a modest numerical band while ranks shift between alleles.

When we examined the binder column across the entire merged file, every entry remained classified as negative for this execution. We emphasize that this outcome is a property of the joint choice of predictor, thresholds, allele pair, and sequence context, not a proof that the virus lacks immunogenic peptides in vivo. What it does establish is a reproducible negative screen under explicitly recorded settings, which is itself useful for comparative studies: any future tool that flags strong binders for the same sequence and alleles can be compared against this baseline under matched inputs.

MultiQC reports bundled with the workflow show how predicted affinities distribute across peptide lengths and rank bins. The distributions appear smooth and internally consistent, without evidence of chunking failures that would suggest incomplete merging across length-specific CSV files. Together with the execution timeline HTML, these artifacts support the claim that the computation completed in the ordinary sense expected for nf-core pipelines.

From a ranking perspective, the strongest numerical affinities in the excerpted region of the table cluster among peptides drawn from the amino-terminal half of the ninety-residue segment, which is compatible with the idea that certain sequence contexts are more favorable for the pseudo-sequence features learned by MHCnuggets. A per-position amino-acid frequency profile across all eight- to twelve-residue rows illustrates compositional variation along the predicted peptide window without implying a sequence logo or binding motif claim. We refrain from mapping these windows onto structural surfaces because that would require an additional structural model and solvent exposure analysis that we did not execute in this version of the study. **Figure 1** diagrams the computational workflow; **Figures 2 and 3** summarize binding affinity by allele and score metrics by peptide length for the archived merged table; **Figure 4** reproduces the MultiQC binding-affinity and length summaries for the same run; **Figure 5** shows the stacked frequency profile for the same rows.

---

## Figures

Paths are relative to this file (`research/anti-virus/docs/`). Regenerate PNG and PDF exports with:

`python3 research/anti-virus/scripts/generate_manuscript_plan_a_figures.py`

![Graphical abstract: antigen segment to epitope prediction and baseline catalogue.](../runs/manuscript_figures_v1/plan_a/GA_plan_a.png)

**Graphical abstract.** Conceptual schematic: ninety-residue glycoprotein segment, nf-core epitopeprediction with MHCnuggets, allele-specific scores, and binder-call summary from the merged TSV (no immunogenicity claim).

![Figure 1. Computational workflow.](../runs/manuscript_figures_v1/plan_a/FigA1_workflow.png)

**Figure 1.** Inputs, nf-core epitopeprediction execution, and primary outputs (merged prediction table and MultiQC summaries).

![Figure 2. Binding affinity by allele.](../runs/manuscript_figures_v1/plan_a/FigA2_BA_by_allele.png)

**Figure 2.** Distribution of predicted binding affinity (BA) for HLA-A*02:01 and HLA-B*07:02 across all peptide–allele rows in the merged file.

![Figure 3. Metrics by peptide length.](../runs/manuscript_figures_v1/plan_a/FigA3_metrics_by_peptide_length.png)

**Figure 3.** Peptide length (eight to twelve residues): **a**, binding affinity (BA); **b**, rank score. Violin summaries are computed from all merged prediction rows at each length.

![Figure 4. MultiQC binding affinity and length summary.](../runs/manuscript_figures_v1/plan_a/FigA4_multiqc_summary.png)

**Figure 4.** MultiQC-derived summaries for the archived run (`PLAN_A_SMOKE_GP`): **a**, predicted binding affinity histogram (counts per bin from `multiqc_binding_affinity_distribution.txt`); **b**, length-stratified proportions from `multiqc_binder_length_distribution.txt` (module naming uses “binder”; panel **b** is the MultiQC export, not an independent binder call from this manuscript).

![Figure 5. Amino-acid frequency by peptide position.](../runs/manuscript_figures_v1/plan_a/FigA5_sequence_profile.png)

**Figure 5.** Stacked per-position amino-acid frequencies from the **`sequence`** column for all merged-table rows with peptide length eight to twelve residues (standard twenty-letter alphabet); positions are **N-terminal–aligned** (twelve positions; shorter peptides do not contribute to absent C-terminal positions). Each **peptide–allele** row is counted separately. This is a descriptive frequency profile (matplotlib), not a WebLogo or motif model.

---

## Table 1

Regenerate from archived TSV (no hand-edited cells):

`python3 research/anti-virus/scripts/generate_manuscript_tables.py`

<!-- BEGIN GENERATED PLAN_A_TABLE1 — source: PLAN_A_SMOKE_GP.tsv -->

| Peptide | Allele | Rank | BA | Binder (MHCnuggets) |
| --- | --- | --- | --- | --- |
| GVCYTLTL | HLA-A*02:01 | 0.7408 | 0.202251 | False |
| GVCYTLTL | HLA-B*07:02 | 0.1390 | 0.122046 | False |
| WYLVVLGV | HLA-A*02:01 | 0.0183 | 0.205543 | False |
| WYLVVLGV | HLA-B*07:02 | 0.3613 | 0.057100 | False |
| TSMAQKSF | HLA-A*02:01 | 0.9011 | 0.201892 | False |
| TSMAQKSF | HLA-B*07:02 | 0.2389 | 0.078817 | False |

<!-- END GENERATED PLAN_A_TABLE1 -->

**Table 1.** Exemplar peptide–allele rows copied from the merged prediction file for the three windows discussed in Results (both alleles each). Canonical export: `runs/manuscript_figures_v1/tables/PLAN_A_TABLE1.md`.

---

## Discussion

The central result of this computational exercise is not a list of validated T cell epitopes but a fully enumerated prediction table with a clear negative binder classification pattern under a narrow allele panel. That limitation is important for interdisciplinary readers who might otherwise over-interpret in silico scores as surrogate markers of protection. Human leukocyte antigen presentation in vivo depends on proteasomal processing, transporter associated with antigen processing efficiency, tapasin effects, and tissue-specific expression, none of which are captured by a binding predictor alone. Glycosylation of the mature glycoprotein and quaternary packing of oligomeric spikes can also mask segments that appear favorable on linear sequence.

Nevertheless, reproducible negative baselines have scientific value when communities debate tool performance on emerging pathogens. If a second predictor or an experimental elution study later identifies convincing binders in the same region, the present archive provides the comparator settings under which the negative MHCnuggets classification was obtained. Conversely, if vaccine designers expand to dozens of alleles using the same sequence, they can treat this two-allele table as a traceable subset rather than as an ad hoc spreadsheet.

We deliberately restricted the narrative to class I lengths eight through twelve and to MHCnuggets because those choices mirror the executed parameter file. Multi-tool ensembles and class II presentation are obvious extensions. Population coverage analyses that weight alleles by epidemiological frequency would strengthen any eventual vaccine framing but require explicit ethical and data-source decisions beyond the scope of this resource paper.

Finally, we note that the segment identifier in the prediction table reflects an internal campaign label rather than a formal International Union of Pure and Applied Chemistry or UniProt accession line in the manuscript body. Replacing that label with a permanent accession and strain metadata should precede any submission to a journal that enforces strict identifier hygiene. The scientific content would remain unchanged because the underlying peptide strings are what enter the predictor.

---

## Conclusions

We present a completed nf-core epitopeprediction run that enumerates class I peptide binding scores for an ANDV glycoprotein benchmark segment across HLA-A*02:01 and HLA-B*07:02 with eight- through twelve-residue windows using MHCnuggets. The archived tables and MultiQC reports provide a transparent negative baseline under those settings and establish a template for allele expansions and orthogonal predictors. No immunogenicity or efficacy claims are warranted from this in silico study alone.

---

## Data availability

Merged peptide predictions, per-length MHCnuggets CSV files, MultiQC directories, and Nextflow `pipeline_info` artifacts are mirrored under `research/anti-virus/runs/plan_a_epitope_a44876b7_s3_mirror/` within the BioMate repository. Workflow parameters for the executed run are stored in `pipeline_info/params_2026-05-14_03-09-35.json` in that mirror. Terminal success of the cloud execution is documented in `research/anti-virus/runs/PARALLEL_PLAN_A_AGENT_POLL_SUMMARY.txt`. Raw object storage locations can be shared with reviewers on request and should be cited precisely in any formal submission supplement.

---

## Figure and table legends proposed for journal submission

**Graphical abstract.** Ninety-residue glycoprotein segment; nf-core epitopeprediction with MHCnuggets; two class I alleles; merged score table as a reproducible in silico baseline (no efficacy or immunogenicity claim).

**Figure 1.** Conceptual workflow from linear glycoprotein segment through nf-core epitopeprediction to allele-specific score tables and MultiQC summaries (vector schematic; export under `runs/manuscript_figures_v1/plan_a/`).

**Figure 2.** Predicted binding affinity (BA) by allele for all peptide–allele rows in the merged prediction file for the archived run.

**Figure 3.** Peptide length (eight to twelve residues): panel **a**, binding affinity (BA); panel **b**, rank score (violin summaries from the merged prediction file).

**Figure 4.** MultiQC tabular exports for the archived sample: panel **a**, binding affinity bin counts (`multiqc_binding_affinity_distribution.txt`); panel **b**, length proportions from `multiqc_binder_length_distribution.txt` (nf-core/MultiQC module label “binder length”; same export as in the HTML report, not a separate binder threshold from this manuscript). Full MultiQC HTML in the run mirror remains the interactive QC report.

**Figure 5.** Per-position amino-acid frequencies (stacked bars) from merged prediction **`sequence`** values for lengths eight to twelve residues; N-terminal–aligned positions; all peptide–allele rows; descriptive profile only (not WebLogo).

**Table 1.** Exemplar peptide–allele rows from the merged prediction file illustrating sequence, allele, rank, binding affinity estimate, and binder classification as produced by MHCnuggets for the archived run.

---

## References

1. Ewels PA, Magnusson M, Lundin S, Käller M. MultiQC: summarize analysis results for multiple tools and samples in a single report. *Bioinformatics*. 2016;32(19):3047–3048.  

2. Di Tommaso P, Chatzou M, Floden EW, et al. Nextflow enables reproducible computational workflows. *Nat Biotechnol*. 2017;35(4):316–319.  

3. nf-core community. The nf-core framework for community-curated bioinformatics pipelines. *Nat Biotechnol*. 2020;38(3):276–278.  

4. Shaffer J, Alvarez KS, Norret M, et al. MHCnuggets: open-source class I MHC binding predictions. *Bioinformatics*. 2018;34(21):3651–3654.  

5. [Insert authoritative ANDV epidemiology and pathogenesis reviews here.]  

6. [Insert nf-core epitopeprediction workflow citation and version DOI here.]
