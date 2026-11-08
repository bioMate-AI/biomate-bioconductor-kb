import hospitalProvenance from "../../public/demo/sysucc_synthetic/provenance.json";
import { coldDemoFor } from "./cold-start-demo-catalog";
/** Prepared examples: datasets verified in docs/20261004_DEMO_DATA_VALIDATION.md. */
export const HOSPITAL_DEMO_PROJECT_NAME = 'Hospital multi-omics — synthetic validation demo';
export const HOSPITAL_EXAMPLES = [
  { label: 'Try hospital demo: synthetic multi-omics integration', prompt: 'Integrate the attached synthetic hospital multi-omics cohort using SNF: rna.csv, protein.csv and methyl.csv have features in rows and samples in columns. Intersect sample IDs, use n_clusters=3, report actual integration QC and cross-layer driver evidence. Do not use ground_truth.csv or true_drivers.csv as input features; these are evaluation truth only. This is the preserved 2026-11-05 synthetic fixture, not hospital patient data or an existing completed run. Inspect README.md and provenance.json. Stop for confirmation before execution.', files: ['rna.csv', 'protein.csv', 'methyl.csv', 'ground_truth.csv', 'true_drivers.csv', 'README.md', 'provenance.json'], root: '/demo/sysucc_synthetic/' },
  { label: 'Try hospital demo: synthetic subtype prediction', prompt: 'Train a subtype classifier on the attached mo_feature_matrix.csv from the synthetic multi-omics validation cohort. Use model_type=sklearn_tabular, label_column=subtype, split=kfold, cv_folds=5. Exclude sample_id from features and keep subtype only as the target. Report fold metrics, uncertainty and leakage checks from the actual new run; do not repeat historical performance as a new result. These are synthetic inputs, not hospital patient records. Inspect README.md and provenance.json. Stop for confirmation before execution.', files: ['mo_feature_matrix.csv', 'README.md', 'provenance.json'], root: '/demo/sysucc_synthetic/' },
] as const;
export const PREPARED_EXAMPLES = [
  { label: 'Try sample data: myasthenia gravis differential expression', prompt: 'Run differential expression on the attached AChR+ myasthenia gravis PBMC demo data (GSE227835, 10 MG patients vs 10 healthy controls). Use the attached sample metadata and contrasts; identify key differentially expressed genes.', files: ['counts_matrix.csv', 'sample_metadata.csv', 'contrasts.csv'] },
  { label: 'Try sample data: human cachexia metabolomics', prompt: 'Run the metaboanalystr workflow using its built-in real human_cachexia demo dataset (77 samples, 63 metabolites). Use the public sample data defaults; do not require my own uploads.' },
  { label: 'Try sample data: EBV antibody titers (ELISA)', prompt: 'Run the analyze_ebv_antibody_titers workflow using its built-in ELISA OD readings and standard-curve demo data; quantify antibody titers (VCA / EA / EBNA1, IgG & IgM) across the EBV-positive, EBV-active and EBV-negative sample groups. Use the public sample-data defaults; do not require my own uploads. (Demonstrates the soluble-protein ELISA → titer → group-comparison method used in immunology/rheumatology biomarker work.)' },
  { label: 'Try sample data: flow cytometry scatter gating', prompt: 'Run analyze_flow_cytometry_immunophenotyping using its built-in real Accuri C6 FCS demo file; apply the default FSC/SSC scatter gate and report measured event counts. This is an H2O instrument blank for file-format/gating demonstration, not marker-positive immune-subset evidence. Use the public sample-data defaults; do not require my own uploads. (For immune-subset quantification, request a labelled biological FCS sample with the required marker channels.)' },
  { label: 'Try sample data: CAR-T construct design', prompt: 'Run the cart_construct_design workflow to design a CD19-targeting CAR construct for B-cell indications: select CAR generation, costimulatory domain and format, and report the design rationale. Use the built-in defaults (target CD19, 2nd generation, auto costimulatory domain). This is an in-silico design exercise, not a validated construct; do not require my own uploads.' },
  { label: 'Try sample data: autoimmune cohort survival (Cox PH)', prompt: 'Run survival_cox_proportional_hazards_regression on the attached demo autoimmune-cohort clinical data (60 patients: time-to-flare in months, event status, age, sex, treatment arm, disease-activity score). Fit a Cox proportional-hazards model to evaluate how treatment arm and disease-activity score affect flare-free survival; report hazard ratios with confidence intervals. (A responder-stratification / survival demonstration on synthetic demo clinical data, not a real cohort.)', files: ['patient_clinical_data.csv'] },
  { label: 'Try sample data: CTCF ChIP-seq peak calling', prompt: 'Run perform_chipseq_peak_calling_with_macs2 using its built-in MACS3 CTCF_SE ChIP and control chr22 50k-read BED demo files. Use the real public demo defaults.' },
  { label: 'Try sample data: histology nuclei segmentation', prompt: 'Run wsi_he_nuclei_segmentation using the built-in real OpenSlide CMU-1-Small-Region.svs demo slide. Use the public sample data defaults.' },
  { label: 'Try sample data: ATAC-seq accessibility', prompt: 'Run analyze_atac_seq_differential_accessibility using its built-in real nf-core treatment and control BAM demo pair. Use the public sample data defaults.' },
  { label: 'Try sample data: proteomics pull-down QC', prompt: 'Run the chemoproteomics_pulldown workflow on its built-in LFQ-Analyst proteinGroups.txt public demo dataset; use the sample-data defaults. (A workflow + QC demonstration on public demo data, not a biologically specific pull-down.)' },
  ...HOSPITAL_EXAMPLES,
] as const;

export async function prepareColdStartExample(text: string): Promise<{ prompt: string; files: File[] }> {
  const example = PREPARED_EXAMPLES.find(item => item.label === text);
  const demo = coldDemoFor(text);
  if (!example && !demo) return { prompt: text, files: [] };
  const names = example ? ('files' in example ? [...example.files] : []) : [...demo!.files, 'demo_notes.md'];
  const root = example ? ('root' in example ? example.root : '/demo/mg_demo/') : '/demo/cold-start/';
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
export async function ensureInternalDemoProject(files: File[], hospital = false): Promise<string> {
  const hospitalDescription = 'Preserved synthetic multi-omics validation inputs for repeatable hospital demonstrations; no patient data.';
  const projectName = hospital ? HOSPITAL_DEMO_PROJECT_NAME : DEMO_PROJECT_NAME;
  const researchGoal = hospital
    ? 'Synthetic multi-omics demonstration using preserved 2026-11-05 validation inputs, not patient records. Integrate rna.csv/protein.csv/methyl.csv on shared sample IDs or train subtype from mo_feature_matrix.csv. Treat ground_truth.csv and true_drivers.csv as evaluation truth only. No previous run or performance is implied. Read README.md and provenance.json.'
    : 'Use the GSE227835 MG PBMC tutorial files: counts_matrix.csv, sample_metadata.csv and contrasts.csv. Compare MG_AChR_pos versus HC. Treat these as demo inputs; no completed assay or workflow result is implied. Inspect the supplied data before drawing conclusions.';
  async function json(url: string, init?: RequestInit) {
    const response = await fetch(url, { credentials: 'include', ...init });
    if (!response.ok) throw new Error(`Demo project setup failed (${response.status}). Please retry.`);
    return response.json();
  }
  const listing = await json('/api/projects');
  let project = listing.projects.find((p: { name: string; status?: string; description?: string }) => p.name === projectName && p.status !== 'archived' && (!hospital || p.description === hospitalDescription));
  if (!project) {
    ({ project } = await json('/api/projects', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: projectName, primaryDomain: 'transcriptomics', description: hospital ? hospitalDescription : 'Prepared public MG PBMC tutorial input files for repeatable demonstrations.', researchGoal }),
    }));
  }
  const existing = await json(`/api/projects/${project.id}/files`);
  for (const file of files) {
    const previous = existing.files.find((f: { name: string }) => f.name === file.name);
    if (previous) {
      const expected = (hospitalProvenance.files as Record<string, { sha256: string }>)[file.name]?.sha256;
      if (hospital && expected && previous.content_hash !== expected) {
        throw new Error(`The demo project already contains a different or unverified ${file.name}. It was not overwritten. Rename that file or use a fresh demo project.`);
      }
      continue;
    }
    const form = new FormData(); form.append('file', file);
    await json(`/api/projects/${project.id}/files/upload`, { method: 'POST', body: form });
  }
  return project.id;
}

/** Prepare a reviewable draft and its explicit project context, never send or run. */
export async function prepareColdStartSelection(text: string): Promise<{ prompt: string; files: File[]; projectId?: string }> {
  const internal = INTERNAL_EXAMPLES.includes(text);
  const hospital = HOSPITAL_EXAMPLES.some(example => example.label === text);
  const result = await prepareColdStartExample(internal ? PREPARED_EXAMPLES[0].label : text);
  if (!internal && !hospital) return result;
  const projectId = await ensureInternalDemoProject(result.files, hospital);
  return { ...result, projectId, prompt: `${internal ? text : result.prompt} Project ID: ${projectId}. Use the project files and attached tutorial inputs. Do not infer prior assay results or completed runs from these input files.` };
}
