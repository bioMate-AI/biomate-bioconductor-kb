import hospitalProvenance from "../../public/demo/sysucc_synthetic/provenance.json";
import { coldDemoFor } from "./cold-start-demo-catalog";
/** Prepared examples: datasets verified in docs/20261004_DEMO_DATA_VALIDATION.md. */
export const HOSPITAL_DEMO_PROJECT_NAME = 'Hospital multi-omics — synthetic validation demo';
export const HOSPITAL_EXAMPLES = [
  { label: 'Integrate a multi-omics cohort (RNA, protein, methylation) with SNF', prompt: 'Integrate the attached multi-omics cohort with SNF: rna.csv, protein.csv and methyl.csv have features in rows and samples in columns. Intersect sample IDs, use n_clusters=3, and report integration QC and cross-layer driver evidence. Do not use ground_truth.csv or true_drivers.csv as input features — they are evaluation truth only. These are synthetic sample files, not patient data; check README.md and provenance.json, and confirm before running.', files: ['rna.csv', 'protein.csv', 'methyl.csv', 'ground_truth.csv', 'true_drivers.csv', 'README.md', 'provenance.json'], root: '/demo/sysucc_synthetic/' },
  { label: 'Train a subtype classifier on a multi-omics feature matrix', prompt: 'Train a subtype classifier on the attached mo_feature_matrix.csv using model_type=sklearn_tabular, label_column=subtype, split=kfold, cv_folds=5. Exclude sample_id from the features and keep subtype as the target only. Report fold metrics, uncertainty and leakage checks. These are synthetic sample files, not patient data; check README.md and provenance.json, and confirm before running.', files: ['mo_feature_matrix.csv', 'README.md', 'provenance.json'], root: '/demo/sysucc_synthetic/' },
] as const;
export const PREPARED_EXAMPLES = [
  { label: 'Find differentially expressed genes in myasthenia gravis vs healthy PBMCs', prompt: 'Run differential expression on the attached AChR-positive myasthenia gravis PBMC data (GSE227835, 10 MG patients vs 10 healthy controls) using the attached sample metadata and contrasts, and identify the key differentially expressed genes.', files: ['counts_matrix.csv', 'sample_metadata.csv', 'contrasts.csv'] },
  { label: 'Analyze the human cachexia metabolomics cohort', prompt: 'Run the metaboanalystr workflow on its built-in human_cachexia dataset (77 samples, 63 metabolites) using the default sample data.' },
  { label: 'Quantify EBV antibody titers (VCA/EA/EBNA1) across sample groups', prompt: 'Run analyze_ebv_antibody_titers on its built-in ELISA OD readings and standard-curve data; quantify VCA, EA and EBNA1 titers (IgG and IgM) across the EBV-positive, EBV-active and EBV-negative groups using the default sample data.' },
  { label: 'Gate flow cytometry scatter and count events', prompt: 'Run analyze_flow_cytometry_immunophenotyping on its built-in Accuri C6 FCS file; apply the default FSC/SSC scatter gate and report event counts. The sample file is an instrument blank for format and gating — request a labelled biological sample for immune-subset quantification.' },
  { label: 'Design a CD19-targeting CAR-T construct', prompt: 'Run cart_construct_design to design a CD19-targeting CAR for B-cell indications — choose the CAR generation, costimulatory domain and format, and explain the rationale. Use the built-in sample defaults (CD19, 2nd generation, auto costimulatory domain). In-silico design, not a validated construct.' },
  { label: 'Model time-to-flare in an autoimmune cohort with Cox regression', prompt: 'Run survival_cox_proportional_hazards_regression on the attached autoimmune-cohort clinical data (60 patients: time-to-flare in months, event status, age, sex, treatment arm, disease-activity score). Fit a Cox proportional-hazards model for how treatment arm and disease-activity score affect flare-free survival, and report hazard ratios with confidence intervals. (Synthetic sample cohort.)', files: ['patient_clinical_data.csv'] },
  { label: 'Call CTCF ChIP-seq peaks with MACS', prompt: 'Run perform_chipseq_peak_calling_with_macs2 on its built-in MACS3 CTCF ChIP and control chr22 BED files using the default sample data.' },
  { label: 'Segment nuclei in a histology whole-slide image', prompt: 'Run wsi_he_nuclei_segmentation on its built-in OpenSlide CMU-1-Small-Region.svs slide using the default sample data.' },
  { label: 'Find differentially accessible regions from ATAC-seq', prompt: 'Run analyze_atac_seq_differential_accessibility on its built-in nf-core treatment and control BAM pair using the default sample data.' },
  { label: 'QC a chemoproteomics pull-down (LFQ proteinGroups)', prompt: 'Run the chemoproteomics_pulldown workflow on its built-in LFQ-Analyst proteinGroups.txt dataset using the default sample data.' },
  ...HOSPITAL_EXAMPLES,
] as const;

/**
 * A prepared example = the natural goal the user sees + its files, plus the
 * bundle's model-facing notes. The notes (dataset identity, column meanings,
 * staged locations) are NEVER put in the composer or the user's bubble: they
 * travel as a hidden `[Prepared inputs: …]` block appended at send time, the
 * same way `[Attached files]` / `[Uploaded datasets]` already do.
 */
export interface PreparedExample { prompt: string; files: File[]; hiddenContext?: string }

export async function prepareColdStartExample(text: string): Promise<PreparedExample> {
  const example = PREPARED_EXAMPLES.find(item => item.label === text);
  const demo = coldDemoFor(text);
  if (!example && !demo) return { prompt: text, files: [] };
  const names = example ? ('files' in example ? [...example.files] : []) : [...demo!.files];
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
  return example ? { prompt: example.prompt, files } : { prompt: goal, files, hiddenContext: demo!.context };
}

/** The hidden block appended to the sent message; the chat bubble strips it. */
export function preparedInputsBlock(context: string): string {
  return `[Prepared inputs: ${context.replace(/[\[\]]/g, '')}]`;
}

export const INTERNAL_EXAMPLES = [
  'Which datasets and sample groups does this project contain?',
  'Summarize counts_matrix.csv and the AChR-positive versus healthy-control contrast in contrasts.csv.',
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
export async function prepareColdStartSelection(text: string): Promise<PreparedExample & { projectId?: string }> {
  const internal = INTERNAL_EXAMPLES.includes(text);
  const hospital = HOSPITAL_EXAMPLES.some(example => example.label === text);
  const result = await prepareColdStartExample(internal ? PREPARED_EXAMPLES[0].label : text);
  if (!internal && !hospital) return result;
  const projectId = await ensureInternalDemoProject(result.files, hospital);
  // Project scope travels structurally (active project id → chat context.projectId);
  // never paste the id into the user's query text.
  return { ...result, projectId, prompt: internal ? text : result.prompt };
}
