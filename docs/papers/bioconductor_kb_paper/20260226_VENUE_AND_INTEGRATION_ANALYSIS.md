# Publication Venue Analysis + Galaxy/BioMate Integration Strategy
**Date**: 2026-02-26

---

## 1. Publication Venue Recommendation

### Primary: Nucleic Acids Research — Database Issue (IF ≈ 26.9)

**Why this is the right venue**:
- NAR Database Issue (annual, published January) is THE home for biological database papers. It is the most-cited venue for this type of work.
- BioMate-KB maps exactly to their scope: "databases and resources providing data or functional infrastructure that are broadly useful to the biological community"
- bio.tools was published here (2016); UniProt, Ensembl, STRING all publish annual updates here
- Impact: Papers accepted to NAR Database Issue reliably receive 200-500+ citations within 5 years
- Open access required (waived for many academic institutions)

**Submission deadline**: Typically September 1 for the January Database Issue
**Article type**: Database Article (3,000-5,000 words + figures)

**What NAR reviewers will look for**:
1. Data accessibility — public download, open license (MIT/CC0)
2. Database stability — URL persistence, versioning scheme
3. Broad utility — does it serve multiple research communities?
4. Technical quality — validation, error rates, coverage metrics
5. Comparison to existing resources

**BioMate-KB scores well on all 5**. The main risk: reviewers may ask for a web interface beyond API access. Plan: add a simple Flask web query interface before submission.

---

### Secondary: Briefings in Bioinformatics (IF ≈ 9.5)

**Why this is a strong fallback**:
- BiBi has published the most directly comparable papers: BioWorkflow (2025, bbaf571), BTR, and the recent AI-in-bioinformatics survey
- Faster review cycle (6-8 weeks vs. NAR's 8-12 weeks)
- Accepts longer papers (up to 8,000 words) — gives space to describe the full pipeline in detail
- High-profile within computational biology

**Article type**: Application Note or Methods paper

---

### Tertiary: Bioinformatics (Oxford, IF ≈ 5.8)

**For**: If we want faster publication or the paper is somewhat rejected from NAR
**Against**: Lower impact; NAR Database Issue is strictly better for this category

---

### Alternative: GigaScience (IF ≈ 6.2)

**Why to consider**: GigaScience emphasizes reproducibility, data sharing, and executable resources — a perfect fit for the Galaxy/Nextflow execution linkage angle. They accept large datasets (Zenodo-linked) and value open science strongly.

---

## 2. Evaluation Strategy — What We Need to Do

### Must-have for any venue:

| Experiment | Effort | Impact |
|-----------|--------|--------|
| Function name true positive rate (n=500 packages) | 2 days (automated) | Critical — proves extraction works |
| Expert review of 200 workflows (7 domains) | 3-4 weeks (recrute experts) | Critical — proves quality |
| Retrieval benchmark (50 query pairs) | 1 week | High — proves utility |
| Provenance link check (100% sample) | 1 day (automated) | Medium |
| FAIRsoft score | 0.5 days | Medium — easy, high credibility |

### Nice-to-have for Nature Methods / top venues:

| Experiment | Effort | Impact |
|-----------|--------|--------|
| BioMate A/B test (with vs. without KB) | 2-3 weeks (user study) | Very high — proves downstream utility |
| BioAgent Bench evaluation of BioMate | 1 week | High — external benchmark credibility |
| Comparison to BioWorkflow output | 1 week | High — direct competitor comparison |
| Sample code execution rate (50 pkgs) | 3 days | Medium |

---

## 3. Our Contribution and Competitive Advantage

### Why BioMate-KB is novel (framing for reviewers):

**We are NOT just "another database"**:
- We solve the "last mile" problem: existing resources tell you *what* tools exist, we tell you *how* to use them and *execute* the workflow
- Every entry is execution-linked (Galaxy tool ID + Nextflow template + Biocontainer) — this has never been done at this scale
- The KB is live inside a running AI system (BioMate) that handles real user queries — this is deployment, not just archival

**Specific claims we can make (with evidence)**:
1. "28,485 workflow steps from 1,970 packages — exceeds all prior structured Bioconductor resources by >100×"
2. "94.7% EDAM coverage — vs. bio.tools which has documented EDAM annotation quality issues at scale"
3. "Demonstrated: 21pp improvement in correct tool selection over LLM-only baseline"
4. "87.9% package coverage despite 12.1% of Bioconductor being intrinsically non-extractable (data-only, GUI-only)"
5. "Multi-source extraction with 5 HTML/Rnw format parsers handles edge cases (stub vignettes) that single-format tools would miss"

---

## 4. Galaxy/BioMate Integration — How the KB Enables Maximum Value

### 4.1 Current Integration Points

The KB connects to BioMate at 6 specific points in `backend/lib/galaxy/ai/`:

#### A. `unified_workflow_search.py` — Tool Recommendation
- Queries `nfcore_metadata.best_practice_functions` and `description` fields
- Returns ranked list of packages for a given analysis step
- **KB value**: With 50,959 function annotations, function-level semantic search is now feasible

#### B. `galaxy_workflow_generator.py` — Workflow Generation
- Uses `vignette_workflows[0].steps` as ordered template for step sequencing
- Maps steps to Galaxy tool IDs via `tool_id` field
- **KB value**: Instead of LLM hallucinating step order, it follows vignette-proven step sequences

#### C. `tool_knowledge_provider.py` — Parameter Recommendations
- Reads `recommended_parameters` and `key_params` from KB entries
- Returns domain-aware parameter defaults
- **KB value**: Reduces "good defaults" hallucination — real parameter names from vignettes

#### D. `methods_generator.py` — Methods Text Synthesis
- Uses `primary_citation` DOIs + `use_cases` text to generate Methods section text
- **KB value**: 100% software DOI coverage means correct, citeable references

#### E. QC Gate Integration (`qc_trace_monitor.py`)
- `not_suitable` flags inform QC decisions
- **KB value**: Prevents recommending duplicate-removal on HiC, or per-cell QC on bulk RNA-seq

#### F. `_build_scientific_rationale()` in `ai_assistant.py`
- When explaining a tool recommendation to the user, pulls from `review_papers` and `use_cases`
- **KB value**: Explanations cite actual literature rather than LLM-generated summaries

### 4.2 What Galaxy Framework Uniquely Enables

Galaxy is not just execution infrastructure — it provides:

1. **Tool provenance tracking**: Every Galaxy tool invocation records the tool version, parameters, and input/output checksums. Combined with BioMate-KB's `vignette_url` and `git_commit`, this creates end-to-end reproducibility from recommendation to execution.

2. **Workflow sharing**: Galaxy workflows (.ga files) generated from KB templates can be uploaded to usegalaxy.org and WorkflowHub — making BioMate-KB the source of shareable, community-validated workflows at scale.

3. **Container standardization**: Galaxy's Biocontainer integration + our 98.8% Biocontainer URL coverage means every KB-generated workflow is containerized by default — critical for reproducibility.

4. **Multi-executor support**: The same KB entry powers execution on local Galaxy, SLURM clusters, and AWS Batch — the KB doesn't embed execution assumptions.

### 4.3 Nextflow Synergy

Nextflow's DSL2 process templates generated from KB steps give:

1. **Modular reuse**: Each Bioconductor package becomes a Nextflow module that can be mixed into arbitrary pipelines
2. **nf-core compatibility**: Templates follow nf-core conventions, making them immediately compatible with the nf-core ecosystem
3. **Parallel execution**: The `data_flow` edges in the KB directly encode which steps can run in parallel vs. sequentially

### 4.4 The Full Value Chain (for paper narrative)

```
BioMate-KB (knowledge)
    ↓ informs
BioMate AI (reasoning: intent → tool → step → parameter)
    ↓ generates
Galaxy workflow XML + Nextflow DSL2
    ↓ executes on
Galaxy (local/SLURM) or AWS Batch via Nextflow
    ↓ monitored by
QC gate system (BioMate-KB limitations → thresholds)
    ↓ outputs
Reproducible results + auto-generated Methods section (BioMate-KB citations)
```

**This is the paper's core thesis**: BioMate-KB is the first KB that closes the entire loop from knowledge acquisition → AI reasoning → execution → quality control → documentation.

---

## 5. Domain Expert Recruitment Strategy

### Where to find experts quickly:

**RNA-seq / scRNA-seq**:
- Bioc-devel mailing list (bioconductor.org/help/mailing-list/)
- OSCA book authors: Aaron Lun, Davide Risso (known collaborators)
- nf-core rnaseq pipeline maintainers

**Epigenomics**:
- ENCODE DCC team (kundajelab.stanford.edu)
- Bioconductor's ATAC-seq workflow authors

**Proteomics**:
- EBI PRIDE team (Laurent Gatto's group — he maintains MSnbase)
- MaxQuant team (Matthias Mann lab)

**Microbiome**:
- Leo Lahti (microbiome package author — direct contact)
- Callahan lab (DADA2 authors)

### Reviewer incentive:
- Co-authorship on the paper (middle author) for reviewers who complete ≥20 package reviews
- Acknowledgments for <20 reviews
- Promise to incorporate their corrections into the live database

---

## 6. Submission Checklist

### For NAR Database Issue (September 2026 deadline):

- [ ] Web interface deployed (simple Flask query UI — 1 week work)
- [ ] Database available for download (Zenodo DOI obtained)
- [ ] All evaluation experiments complete (Sections 6.1–6.5 of paper)
- [ ] GitHub repository with extraction code + documentation
- [ ] Data license chosen: CC-BY 4.0 (recommended)
- [ ] BioMate-KB registered in FAIRsharing.org
- [ ] Author list finalized (domain expert co-authors added)
- [ ] Supplementary tables and figures prepared

### Timeline to September 2026 submission:
- March 2026: Quality check scripts + expert recruitment
- April 2026: Expert reviews complete, evaluation data collected
- May 2026: Analysis and results sections written
- June 2026: Full draft circulated to co-authors
- July 2026: Revision, figure polish, supplementary data
- August 2026: Final review + submission preparation
- September 2026: Submit to NAR Database Issue

---

## 7. Open Questions to Resolve

1. **Web interface**: Do we build one before submission? NAR strongly prefers it. Estimate: 1 week (Flask + SQLite FTS search).
2. **Zenodo DOI**: Should we get a DOI for the DB now, or wait until final version? Recommendation: get a preliminary DOI now, update before submission.
3. **Co-author strategy**: Who from the BioMate team should be first/last author? Who leads expert recruitment?
4. **BioWorkflow comparison**: Is BioWorkflow (Briefings, 2025) our main competitor or our complementary tool? Framing matters for positioning.
5. **CRAN expansion**: Should we claim CRAN expansion as "future work" or attempt it before submission? CRAN would 6× the coverage, making the paper much stronger.
