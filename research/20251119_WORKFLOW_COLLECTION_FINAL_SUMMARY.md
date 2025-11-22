# BioMate Workflow Collection - Final Summary

**Date:** 2025-11-19
**Status:** Complete

---

## Overview

Evaluated and curated Galaxy workflows from colleague's IWC collection to complement the existing nf-core converted workflows.

---

## Collections

### 1. Original nf-core Workflows (94 files)
- **Location:** `/home/yzhang/biomate/backend/galaxy_workflows/`
- **Format:** .ga (Galaxy Archive)
- **Source:** Converted from nf-core subworkflows
- **Tool IDs:** Simple format (`bwa_mem`, `samtools_sort`)
- **Purpose:** Modular building blocks for BioMate

### 2. Curated IWC Workflows (769 files)
- **Location:** `/home/yzhang/biomate/research/final_curated_workflows/`
- **Format:** .ga (Galaxy Archive)
- **Source:** Intergalactic Workflow Commission
- **Tool IDs:** ToolShed format (`toolshed.g2.bx.psu.edu/repos/...`)
- **Purpose:** Complete analysis pipelines as templates

---

## Evaluation Results

| Metric | Value |
|--------|-------|
| Total evaluated | 951 |
| Quality threshold | 60/100 |
| Passed quality | 928 |
| After deduplication | 769 |
| Rejected | 23 |

### Quality Criteria Applied

**Positive factors:**
- Trusted owner (IWC, iuc, devteam, etc.) +25
- Meaningful annotation +20
- Complex workflow (10+ steps) +20
- Creator attribution +15
- License +10
- Standard bioinformatics tools +15

**Negative factors:**
- Ad-hoc pattern ("constructed from history") -30
- No annotation -15
- Hardcoded filenames -10

---

## Domain Coverage (IWC Collection)

| Domain | Count |
|--------|-------|
| ChIP-seq | 90 |
| Assembly | 34 |
| ATAC-seq | 32 |
| CUT&RUN/CUT&Tag | 32 |
| VGP (Genome Assembly) | 25 |
| Hi-C | 15 |
| RNA-seq | 11 |
| COVID-19 | 10 |
| Metaproteomics | 5 |
| Single-cell | 2 |

---

## Tool System Architecture

### How It Works

1. **Semantic Search** - Users query by intent, not tool ID
2. **Database** - 9,226 tools indexed with metadata and installation info
3. **On-demand Installation** - Latest version fetched when needed
4. **IWC Workflows** - Serve as templates for analysis patterns

### Tool Sources

| Source | Format | Count |
|--------|--------|-------|
| ToolShed | Full URL with version | 471 |
| Built-in Galaxy | Tool name only | 36 |
| nf-core custom | `nfcore_toolname` | 20 |
| BioMate custom | `biomate_toolname` | 1 |

---

## Files Generated

| File | Description |
|------|-------------|
| `final_curated_workflows/` | 769 .ga workflow files |
| `20251119_0928_WORKFLOW_EVALUATION_REPORT.md` | Detailed evaluation scores |
| `20251119_0930_DEDUPLICATED_WORKFLOW_REPORT.md` | Deduplication results |
| `20251119_1026_TOOL_INVENTORY.json` | Complete tool mapping |
| `20251119_1026_TOOL_INVENTORY_REPORT.md` | Tool analysis |
| `scripts/evaluate_workflows.py` | Reusable evaluation script |
| `scripts/deduplicate_workflows.py` | Deduplication script |
| `scripts/create_tool_inventory.py` | Tool inventory generator |

---

## How to Use

### IWC Workflows as Templates

The curated IWC workflows are **reference templates**, not directly executable:

1. User describes analysis intent
2. System uses semantic search to find relevant workflow template
3. System maps workflow tools to available BioMate tools
4. Missing tools are installed on-demand (latest version)
5. Workflow is adapted and executed

### Adding to BioMate

The 769 curated workflows can be used for:
- Training AI on analysis patterns
- Template library for workflow suggestions
- Reference for tool combinations
- Quality benchmark for user-submitted workflows

---

## Trusted Owners

Workflows from these sources get +25 quality points:

| Owner | Description |
|-------|-------------|
| iwc | Intergalactic Workflow Commission |
| iuc | Intergalactic Utilities Commission |
| devteam | Galaxy core development team |
| galaxyp | Galaxy Proteomics community |
| nml | National Microbiology Laboratory |
| ebi-gxa | EBI Gene Expression Atlas |
| bgruening | Major Galaxy contributor |
| galaxyproject | Official Galaxy Project |
| usegalaxy-eu | European Galaxy server team |

---

## Next Steps

1. **Integrate with AI** - Use workflows for training semantic tool search
2. **Template matching** - Build system to match user intent to workflow templates
3. **Tool coverage** - Ensure all IWC workflow tools have installation paths
4. **Version management** - Strategy for handling version updates

---

## Conclusion

The workflow collection now includes:
- **94 nf-core workflows** - Modular building blocks with simple tool IDs
- **769 IWC workflows** - Complete analysis templates with ToolShed references

Together they provide comprehensive coverage of bioinformatics analysis patterns for BioMate's AI-driven workflow system.
