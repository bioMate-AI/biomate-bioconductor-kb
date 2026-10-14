import { coldDemoFor } from "./cold-start-demo-catalog";
/** Prepared examples: datasets verified in docs/20261004_DEMO_DATA_VALIDATION.md. */
export const PREPARED_EXAMPLES = [
  { label: 'Try sample data: myasthenia gravis differential expression', prompt: 'Run differential expression on the attached AChR+ myasthenia gravis PBMC demo data (GSE227835, 10 MG patients vs 10 healthy controls). Use the attached sample metadata and contrasts; identify key differentially expressed genes.', files: ['counts_matrix.csv', 'sample_metadata.csv', 'contrasts.csv'] },
  { label: 'Try sample data: human cachexia metabolomics', prompt: 'Run the metaboanalystr workflow using its built-in real human_cachexia demo dataset (77 samples, 63 metabolites). Use the public sample data defaults; do not require my own uploads.' },
  { label: 'Try sample data: EBV antibody titers (ELISA)', prompt: 'Run the analyze_ebv_antibody_titers workflow using its built-in ELISA OD readings and standard-curve demo data; quantify antibody titers (VCA / EA / EBNA1, IgG & IgM) across the EBV-positive, EBV-active and EBV-negative sample groups. Use the public sample-data defaults; do not require my own uploads. (Demonstrates the soluble-protein ELISA → titer → group-comparison method used in immunology/rheumatology biomarker work.)' },
  { label: 'Try sample data: CTCF ChIP-seq peak calling', prompt: 'Run perform_chipseq_peak_calling_with_macs2 using its built-in MACS3 CTCF_SE ChIP and control chr22 50k-read BED demo files. Use the real public demo defaults.' },
  { label: 'Try sample data: histology nuclei segmentation', prompt: 'Run wsi_he_nuclei_segmentation using the built-in real OpenSlide CMU-1-Small-Region.svs demo slide. Use the public sample data defaults.' },
  { label: 'Try sample data: ATAC-seq accessibility', prompt: 'Run analyze_atac_seq_differential_accessibility using its built-in real nf-core treatment and control BAM demo pair. Use the public sample data defaults.' },
  { label: 'Try sample data: proteomics pull-down QC', prompt: 'Run the chemoproteomics_pulldown workflow on its built-in LFQ-Analyst proteinGroups.txt public demo dataset; use the sample-data defaults. (A workflow + QC demonstration on public demo data, not a biologically specific pull-down.)' },
] as const;

export async function prepareColdStartExample(text: string): Promise<{ prompt: string; files: File[] }> {
  const example = PREPARED_EXAMPLES.find(item => item.label === text);
  const demo = coldDemoFor(text);
  if (!example && !demo) return { prompt: text, files: [] };
  const names = example ? ('files' in example ? [...example.files] : []) : [...demo!.files, 'demo_notes.md'];
  const root = example ? '/demo/mg_demo/' : '/demo/cold-start/';
  const files = await Promise.all(names.map(async name => {
    const response = await fetch(`${root}${name}`);
    if (!response.ok) throw new Error(`Could not load sample file ${name}`);
    const blob = await response.blob();
    if (!blob.size || blob.type.includes('text/html')) throw new Error(`Sample file ${name} is unavailable`);
    return new File([blob], name, { type: blob.type || 'application/octet-stream' });
  }));
  // Context specifies exact entities and contrasts; no unresolved “this target”.
  // Incompatible generic hints (e.g. GRCh38) are replaced by the fixture's build.
  const goal = demo ? text.replace(/ Human GRCh38\./g, '').replace(/this protein sequence and tell me where to trust it: .+$/, 'the attached lysozyme sequence and tell me where to trust it.') : text;
  return { prompt: example ? example.prompt : `${goal}\n\nPrepared demo context:\n${demo!.context}`, files };
}

export const INTERNAL_EXAMPLES = [
  'Explore the prepared MG demo project: which datasets and sample groups are available?',
  'In the prepared MG demo project, summarize counts_matrix.csv and the MG_AChR_pos versus HC contrast in contrasts.csv.',
];
export const DEMO_PROJECT_NAME = 'MG PBMC — sample data demo';

/** Reuse the user's fixture; resume missing uploads after an interrupted setup. */
export async function ensureInternalDemoProject(files: File[]): Promise<string> {
  async function json(url: string, init?: RequestInit) {
    const response = await fetch(url, { credentials: 'include', ...init });
    if (!response.ok) throw new Error(`Demo project setup failed (${response.status}). Please retry.`);
    return response.json();
  }
  const listing = await json('/api/projects');
  let project = listing.projects.find((p: { name: string; status?: string }) => p.name === DEMO_PROJECT_NAME && p.status !== 'archived');
  if (!project) {
    ({ project } = await json('/api/projects', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: DEMO_PROJECT_NAME, primaryDomain: 'transcriptomics', description: 'Prepared public MG PBMC tutorial input files for repeatable demonstrations.', researchGoal: 'Use the GSE227835 MG PBMC tutorial files: counts_matrix.csv, sample_metadata.csv and contrasts.csv. Compare MG_AChR_pos versus HC. Treat these as demo inputs; no completed assay or workflow result is implied. Inspect the supplied data before drawing conclusions.' }),
    }));
  }
  const existing = await json(`/api/projects/${project.id}/files`);
  for (const file of files) {
    if (existing.files.some((f: { name: string }) => f.name === file.name)) continue;
    const form = new FormData(); form.append('file', file);
    await json(`/api/projects/${project.id}/files/upload`, { method: 'POST', body: form });
  }
  return project.id;
}
