# Canonical catalog-count reconciliation

**Date:** 2026-10-04
**Why:** the workflow count was cited three ways (2,455 / 4,017 / 4,200) across CLAUDE.md, the MCP
server instructions, and the on-prem manuscripts. External assets (papers, deck, site, app listings)
must cite one canonical number, with the *validated* subset stated separately. These numbers are the
ground truth queried directly from the catalog DB.

## Source of truth
`backend/database/galaxy_ai_tools.db`, table `workflows` (queried 2026-10-04).

## Canonical numbers
| Figure | Value | Query |
|---|---:|---|
| **Total workflows (catalog)** | **4,209** | `SELECT COUNT(*) FROM workflows` |
| Indexed tools | 12,312 | `SELECT COUNT(*) FROM tools` |
| Distinct domain tags (raw) | 42 | `SELECT COUNT(DISTINCT domain) FROM workflows WHERE TRIM(domain)<>''` |
| Curated domains (headline) | ~36 | raw 42 minus small near-duplicate/overlap tags |
| **Validated subset (clean real-exec)** | **1,092** | `real_exec_status IN ('ok','ok_warnings')` (690 strictly `ok` + 402 `ok_warnings`) |
| Produced some output | 1,791 | `real_exec_produced` non-empty |

### Composition by source
bioconductor 3,326 · biomni_nextflow 397 · nfcore 230 · nfcore_subwf 93 · nextflow 63 ·
biomate-ai-tools 43 · biomate 35 · metaboanalystr-suite 8 · others ≤4 each.

### Top domains (by workflow count)
transcriptomics 1,695 · genomics 756 · epigenomics 265 · drug_discovery 200 · proteomics 186 ·
variant_calling 181 · general 153 · systems_biology 108 · single_cell 100 · imaging 77 ·
metagenomics 75 · metabolomics 65 · pharmacology 39 · genetics 35 · … (42 tags total).

## Reconciliation of the three prior figures
- **2,455 / 34 domains** (CLAUDE.md) — **STALE**; predates catalog growth. Corrected here.
- **4,017 / 36 domains** (MCP server instructions; `docs/20260918_ONPREM_DOMAIN_LLM_MANUSCRIPT.md`) — an
  earlier snapshot of the same growing catalog.
- **4,200 / 36 domains / 12,312 tools** (`docs/20260912_onprem_llm/MANUSCRIPT.md`) — a rounded recent
  snapshot; now exactly **4,209** / 12,312 tools.

## How to cite going forward (external)
- Catalog breadth: **"~4,200 workflows (4,209 as of 2026-10-04) across ~36 domains, indexed over 12,312
  tools."**
- Validated capability (state SEPARATELY, never conflated): **"1,092 workflows carry clean
  real-execution evidence (end-to-end run produced valid outputs)."**
- Never present the 4,209 catalog count as the validated/tested number.

## Follow-ups
- MCP server's live count string (backend-generated) should be regenerated so it emits 4,209 too.
- The on-prem manuscripts should adopt 4,209 / 1,092 and drop 4,017/4,200.
