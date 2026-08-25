// Format → interactive-viewer mapping.
//
// The interactive tool for a *typed* dataset is deterministic from its Galaxy datatype, so callers
// should NOT make the user pick from a dropdown — auto-select the primary viewer by format and offer
// the rest as "Open with". Jupyter/RStudio are the universal escape-hatch and are always available as
// alternatives (and are the default when the format isn't a known viewer type).
//
// Only tools ENABLED in backend/config/interactivetools_conf.xml belong here (the curated set).

export type ViewerKey =
  | 'jupyter' | 'rstudio' | 'cellxgene' | 'isee'
  | 'vcf_iobio' | 'bam_iobio' | 'higlass' | 'pavian';

/** Galaxy tool_id for each viewer (what /api/interactive/launch expects). */
export const VIEWER_TOOL_ID: Record<ViewerKey, string> = {
  jupyter: 'interactive_tool_jupyter_notebook',
  rstudio: 'interactive_tool_rstudio',
  cellxgene: 'interactive_tool_cellxgene',
  isee: 'interactive_tool_isee',
  vcf_iobio: 'interactive_tool_vcf_iobio',
  bam_iobio: 'interactive_tool_bam_iobio',
  higlass: 'interactive_tool_higlass',
  pavian: 'interactive_tool_pavian',
};

export const VIEWER_META: Record<ViewerKey, { name: string; description: string; bestFor: string }> = {
  jupyter:   { name: 'Jupyter Notebook', description: 'Python 3 interactive environment', bestFor: 'Custom analysis, visualization, ML' },
  rstudio:   { name: 'RStudio',          description: 'R 4.3 / Bioconductor IDE',          bestFor: 'Statistics, Bioconductor packages' },
  cellxgene: { name: 'CellxGene',        description: 'Interactive single-cell viewer',    bestFor: 'Single-cell RNA-seq exploration' },
  isee:      { name: 'iSEE',             description: 'Bioconductor SingleCellExperiment explorer', bestFor: 'Single-cell / SummarizedExperiment' },
  vcf_iobio: { name: 'vcf.iobio',        description: 'Real-time VCF statistics',          bestFor: 'Variant-call QC / summary' },
  bam_iobio: { name: 'bam.iobio',        description: 'Real-time BAM statistics',          bestFor: 'Alignment QC / summary' },
  higlass:   { name: 'HiGlass',          description: 'Multiscale genome / Hi-C browser',  bestFor: 'Hi-C matrices, bigwig/bed tracks' },
  pavian:    { name: 'Pavian',           description: 'Metagenomics taxonomy explorer',    bestFor: 'Kraken/Bracken reports' },
};

// Primary + ordered viewers per Galaxy datatype/extension (lowercased). First = primary.
// Formats not listed fall through to the generic escape-hatch (Jupyter/RStudio).
const BY_FORMAT: Record<string, ViewerKey[]> = {
  h5ad: ['cellxgene', 'isee'],
  loom: ['cellxgene'],
  anndata: ['cellxgene', 'isee'],
  rdata: ['isee', 'rstudio'],
  rds: ['isee', 'rstudio'],
  vcf: ['vcf_iobio'],
  vcf_bgzip: ['vcf_iobio'],
  bam: ['bam_iobio'],
  cool: ['higlass'],
  mcool: ['higlass'],
  bigwig: ['higlass'],
  bed: ['higlass'],
  bedgraph: ['higlass'],
};

// Always-available universal viewers (code escape-hatch).
const GENERIC: ViewerKey[] = ['jupyter', 'rstudio'];

/**
 * Recommend interactive viewers for a dataset format.
 * Returns the primary (auto-launch) viewer + ordered alternatives ("Open with").
 * Generic Jupyter/RStudio are always appended as alternatives (or become the primary
 * when the format has no dedicated viewer).
 *
 * Note: kraken/bracken reports are `tabular` in Galaxy (ambiguous) — for plain tabular we default to
 * the generic viewers and surface Pavian as an alternative, since we can't tell a taxonomy report
 * from any other table by extension alone.
 */
export function recommendViewers(format?: string): { primary: ViewerKey; alternatives: ViewerKey[] } {
  const fmt = (format || '').toLowerCase().trim();
  let matched = BY_FORMAT[fmt] || [];
  if ((fmt === 'tabular' || fmt === 'tsv' || fmt === 'txt') && !matched.length) {
    matched = ['pavian']; // offered as an alternative, not primary (see note above)
    const ordered = [...GENERIC, ...matched];
    return { primary: ordered[0], alternatives: ordered.slice(1) };
  }
  const ordered = [...matched, ...GENERIC.filter((g) => !matched.includes(g))];
  return { primary: ordered[0] || 'jupyter', alternatives: ordered.slice(1) };
}
