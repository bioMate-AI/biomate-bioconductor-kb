# GitHub Repository Setup Checklist
**Goal:** Make BioMate discoverable by researchers searching GitHub for bioinformatics tools

---

## 1. Repository Topics to Add
Go to the repo → Settings → Topics (or the gear icon on the main page)

Add ALL of these (GitHub allows up to 20):
```
bioinformatics
nextflow
nf-core
galaxy
workflow-automation
rna-seq
single-cell
metagenomics
proteomics
cryo-em
drug-discovery
qc-governance
reproducibility
python
ai
life-sciences
genomics
wgs
atac-seq
chip-seq
```

---

## 2. Repository Description (one-liner)
```
AI-powered research execution platform for life sciences — describe your analysis, BioMate runs the Nextflow pipeline. 10,595 validated tools, evidence-graded QC.
```

---

## 3. README First 3 Lines (critical — this is what shows in search)
The first 3 lines of the README are shown in GitHub search results. They must be crystal clear:

```markdown
# BioMate — AI-Powered Bioinformatics Execution

Describe your analysis in plain English → BioMate generates, configures, and runs the Nextflow workflow.
No Nextflow experience required. Evidence-graded QC governance built in.
```

---

## 4. README Badges to Add (social proof, credibility)
```markdown
[![Beta](https://img.shields.io/badge/beta-invite%20only-blue)](https://biomate.ai)
[![Tools](https://img.shields.io/badge/tools-10%2C595%20validated-green)]()
[![Workflows](https://img.shields.io/badge/workflows-967%20templates-green)]()
[![License](https://img.shields.io/badge/license-MIT-blue)]()
```

---

## 5. Open-Source a Small Utility (drives organic stars)
The fastest way to get GitHub stars from bioinformatics researchers is to release something immediately useful.

**Recommendation: Release the QC Threshold Database as a standalone repo**

`biomate-qc-thresholds` — a JSON/YAML file of evidence-graded QC thresholds for RNA-seq, scRNA-seq, WGS/WES, ATAC-seq, ChIP-seq, metagenomics, cryo-EM. Each threshold with:
- The threshold value
- Evidence tier (GOLD/SILVER/BRONZE)
- The citation (DOI)
- Notes on protocol-specific adjustments

This is genuinely useful to any bioinformatician independently of BioMate — and every person who uses it is a potential BioMate user.

---

## 6. Pin 2-3 Repositories
On the organization page, pin:
1. Main BioMate repo
2. `biomate-qc-thresholds` (once created)
3. A demo/example workflow repo

---

## 7. GitHub Discussions
Enable GitHub Discussions on the repo and seed with:
- "What workflows do you most want to see added?"
- "Share your QC threshold recommendations"
- "Questions & troubleshooting"

This creates an organic community space that appears in Google searches.

---

## 8. Contribute to nf-core Discussions
Search GitHub for nf-core issues/discussions where people ask about:
- "How do I configure parameters for FFPE samples?"
- "What QC thresholds should I use?"
- "Can nf-core run on AWS Batch?"

Answer helpfully, mention BioMate as a way to handle these without manual config.
Don't spam — 1-2 thoughtful answers per week is enough.

Target repos: `nf-core/rnaseq`, `nf-core/sarek`, `nf-core/mag`, `nf-core/scrnaseq`
