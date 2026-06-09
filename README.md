# BioMate-KB — Bioconductor Skills

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20616355.svg)](https://doi.org/10.5281/zenodo.20616355)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20616543.svg)](https://doi.org/10.5281/zenodo.20616543)

> A knowledge base of 15,641 real-execution-validated Bioconductor workflow steps — the public skill bundle behind [BioMate AI](https://www.biomate.ai). Methodology and validation documented in two preprints (see [Citation](#citation)).

**Top 100 Bioconductor packages by official download score, formatted as Claude Code Skills.**

A skill bundle in [Claude Code Skills](https://docs.anthropic.com/en/docs/claude-code/skills-overview) format, covering the most-used 100 Bioconductor packages from the BioMate-KB knowledge base. Each skill teaches Claude when to choose a package, what parameters to set, how to interpret results, and what pitfalls to avoid.

## What's here

```
skills/
├── transcriptomics/    (33 skills — DESeq2, edgeR, limma, fgsea, ...)
├── genomics/           (23 skills — GenomicRanges, Rsamtools, ...)
├── general/            (16 skills — utility / cross-domain)
├── proteomics/         (8  skills — MSstats, MSnbase, Spectra, ...)
├── variant-calling/    (4  skills — VariantAnnotation, maftools, ...)
├── metagenomics/       (4  skills — phyloseq, ANCOMBC, dada2, ...)
├── single-cell/        (3  skills — Seurat, scran, scater, ...)
├── epigenomics/        (3  skills — ChIPseeker, DiffBind, methylKit, ...)
├── enrichment/         (2  skills — clusterProfiler, ReactomePA, ...)
├── annotation/         (2  skills — biomaRt, AnnotationHub, ...)
└── imaging/            (2  skills)
```

This bundle is intentionally focused on the **highest-traffic packages** — the top 100 accounts for roughly 60% of all Bioconductor downloads. The full BioMate KB covers all 1,818 active Bioconductor packages and is available via [BioMate Cloud](https://biomate.ai).

Each `SKILL.md` has:
- **YAML frontmatter**: `name`, `description`, `when_to_use`, `user-invocable: false`
- **Best Practices** — what to do and how to configure
- **Key Parameters** — recommended values with context
- **Result Interpretation** — how to read outputs
- **Common Pitfalls** — what to warn users about
- **Data Requirements** — expected input format
- **Alternatives** — when to suggest a different package

## Want the full collection?

This bundle covers the top 100 Bioconductor packages. **[BioMate AI](https://www.biomate.ai)** gives you:

- **Full coverage** — all 1,818+ active Bioconductor packages plus 2,455 curated workflows across genomics, transcriptomics, proteomics, drug discovery, and more
- **Nothing to install or manage** — analyses just run, at any scale
- **Output visualization and analysis** — interactive charts, QC dashboards, and AI-generated findings built in
- **Report generation** — one-click publication-ready methods reports and summary documents

**Start using BioMate AI for free at [www.biomate.ai](https://www.biomate.ai)**
Questions or collaboration inquiries: [contact@biomate.ai](mailto:contact@biomate.ai)

## How to use

```bash
# Clone
git clone https://github.com/bioMate-AI/biomate-bioconductor-kb.git
cd biomate-bioconductor-kb

# Install all skills into Claude Code (global)
find skills -name "SKILL.md" | while read f; do
  pkg=$(dirname "$f" | xargs basename)
  cp "$f" ~/.claude/skills/bioconductor-${pkg}.md
done
```

Or copy a single domain:

```bash
# Only RNA-seq DE skills
find skills/transcriptomics -name "SKILL.md" | while read f; do
  pkg=$(dirname "$f" | xargs basename)
  cp "$f" ~/.claude/skills/bioconductor-${pkg}.md
done
```

Each `SKILL.md` is a self-contained Claude Code skill file — Claude discovers it automatically once it's in `~/.claude/skills/` (global) or `.claude/skills/` (project-level).

## Ranking source

Packages are ordered by Bioconductor's official monthly download score:
- Source: <https://bioconductor.org/packages/stats/bioc/bioc_pkg_scores.tab>
- Snapshot taken: 2026-05-21
- Top 100 of 3,058 ranked Bioconductor software packages (covers 3.3% of the catalog by count, ~60% by traffic)

## About these skills

Each skill captures the *knowledge* for one Bioconductor package — when and why to use it, key parameters, assumptions, common pitfalls, alternatives, and citations — grounded in the package's own documentation.

Built by the team behind [BioMate](https://biomate.ai).

## License

- **Skill content** (`skills/**/*.md`, `MANIFEST.json`): **CC-BY-4.0** — share + adapt with attribution.
- **Extraction scripts** (`extraction/*.py`): **Apache-2.0** — use, modify, distribute.
- **Underlying Bioconductor packages** retain their own (mostly Artistic-2.0 / GPL) licenses.

## Citation

If you use BioMate-KB, please cite the two companion papers:

> Zhang, Y. (2026). *BioMate-KB: A Real-Execution-Validated Workflow Knowledge Base for Bioconductor* (v3). Zenodo. https://doi.org/10.5281/zenodo.20616355

> Zhang, Y. (2026). *Structure Grounding Is Not Enough: Real Execution as the Ground Truth for LLM-Generated Bioinformatics Workflows* (v3). Zenodo. https://doi.org/10.5281/zenodo.20616543

These are the **concept DOIs** (Zenodo "Cite all versions") — they always resolve to the latest version. To pin exactly v3, use the version DOIs: BioMate-KB `10.5281/zenodo.20616356` · Structure Grounding `10.5281/zenodo.20616544`.

## Regenerating the bundle

```bash
# Re-fetch the latest Bioconductor download scores
curl -O https://bioconductor.org/packages/stats/bioc/bioc_pkg_scores.tab

# Regenerate the skill bundle (top 100 by default)
python3 extraction/generate_bundle.py --top 100

# Single package
python3 extraction/extract_skill.py \\
    --db <path-to-biomate-knowledge-db> \\
    --pkg DESeq2 \\
    --out my-deseq2-skill.md
```

The `extraction/` scripts generate each skill from the package's public documentation and curated knowledge.

## Versioning

This is **v1.0.0** of the bundle. Future versions will track:
- New Bioconductor releases (currently pinned to 3.20)
- Expanded coverage (top-1000 if community demand justifies)
- Refined SKILL.md sections (Q&A, gotchas, additional examples)

## Contributing

Open an issue or PR for:
- Errors in any SKILL.md
- Suggestions for new sections to extract
- Packages missing from the top-100 that should be included

## Acknowledgments

Bioconductor download statistics published by the Bioconductor Core Team. SKILL.md format from [Anthropic Claude Code](https://docs.anthropic.com/en/docs/claude-code/skills-overview).
