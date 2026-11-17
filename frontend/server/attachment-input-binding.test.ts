/**
 * The chat chokepoints that bind an attached file to the chosen workflow's
 * input (founder report, 2026-11-11):
 *
 *  - generateWorkflow(): the file→param mapping used to be a fixed list of
 *    canonical names, so "Train a potency predictor…" + bace_assays.csv left
 *    the workflow's required `input_smiles` empty ("1 required parameter need
 *    to be filled") although the right file was attached.
 *  - groundInlineParameters(): an upstream extractor emitted the bare FILE NAME
 *    as a parameter value ("antibodies": "nanobody_candidates.fasta"), which
 *    resolves to nothing at run time.
 */
import { describe, expect, it, vi } from 'vitest';
import { GalaxyAssistant, groundInlineParameters, attachmentBoundParams } from './galaxy-assistant';

const BACE_MESSAGE =
  'Train a potency predictor on our in-house assay data.\n\n' +
  '[Attached files: bace_assays.csv]\n' +
  '[Uploaded datasets: bace_assays.csv: dataset_id=78ff4255-d078-4745-96a1-e421acf23212, ' +
  'galaxy_dataset_id=dbc510811ab4034e, s3_uri=s3://biomate-nextflow-work/uploads/78ff4255/bace_assays.csv]';
const BACE_URI = 's3://biomate-nextflow-work/uploads/78ff4255/bace_assays.csv';

const NANOBODY_MESSAGE =
  'Design nanobody candidates against this epitope.\n\n' +
  '[Attached files: 6Z43.pdb, 6Z43.fasta, nanobody_candidates.fasta, nanobody_constraints.json]\n' +
  '[Uploaded datasets: 6Z43.pdb: dataset_id=a1, s3_uri=s3://b/a1/6Z43.pdb; ' +
  '6Z43.fasta: dataset_id=a2, s3_uri=s3://b/a2/6Z43.fasta; ' +
  'nanobody_candidates.fasta: dataset_id=a3, s3_uri=s3://b/a3/nanobody_candidates.fasta; ' +
  'nanobody_constraints.json: dataset_id=a4, s3_uri=s3://b/a4/nanobody_constraints.json]';

/** Live "Scaffold Hopping" schema (dev /api/workflows/search, 2026-11-11). */
function scaffoldHoppingResponse() {
  return {
    success: true,
    workflow_name: 'Scaffold Hopping',
    nextflow_path: 'nextflow_nfcore/subworkflows/drug_discovery/scaffold_hopping/main.nf',
    workflow_ga: {
      name: 'Scaffold Hopping',
      required_params: [
        { name: 'input_smiles', type: 'string', required: true, default: null, description: 'path to SMILES file (one "SMILES compound_id" per line)' },
      ],
      optional_params: [
        { name: 'reference_smiles', type: 'string', required: false, default: 'CC(=O)Nc1ccc(O)cc1', description: 'acetaminophen as default reference' },
        { name: 'max_candidates', type: 'integer', required: false, default: 20, description: 'maximum scaffold candidates to report' },
      ],
    },
  };
}

/** Live "Antibody Antigen Complex" schema — inline-content params, no file input. */
function antibodyComplexResponse() {
  return {
    success: true,
    workflow_name: 'Antibody Antigen Complex',
    workflow_ga: {
      name: 'Antibody Antigen Complex',
      required_params: [],
      optional_params: [
        { name: 'antibodies', type: 'string', required: false, default: '[{"id": "fmc63", "vh": "EVKLQ"}]', description: 'Workflow parameter: Antibodies' },
        { name: 'antigen_chains', type: 'string', required: false, default: '{"A": "PEELG"}', description: 'Workflow parameter: Antigen Chains' },
        { name: 'target', type: 'string', required: false, default: 'demo_target', description: 'Workflow parameter: Target' },
      ],
    },
  };
}

function assistantReturning(response: any) {
  const a = Object.create(GalaxyAssistant.prototype) as any;
  a.galaxyAPI = { generateWorkflow: vi.fn(async () => response) };
  a._inferDomainWithLLM = vi.fn(async () => undefined);
  return a;
}

/** generateWorkflow(intent, datasets, inline, context, …, selection, attachmentMessage) */
function callGenerate(a: any, intent: string, message: string) {
  return a.generateWorkflow(intent, [], {}, undefined, undefined, undefined, undefined, undefined, undefined, undefined, message);
}

describe('generateWorkflow — attachment binding', () => {
  it('binds the attached CSV to the required SMILES file input (panel + executor read the same value)', async () => {
    const a = assistantReturning(scaffoldHoppingResponse());
    const out = await callGenerate(a, 'train a potency predictor', BACE_MESSAGE);
    const ga = out.workflow_ga;
    expect(ga.required_params[0].value).toBe(BACE_URI);
    expect(ga.required_params[0].autoFilled).toBe(true);
    expect(ga.inline_parameters.input_smiles).toBe(BACE_URI);
    expect(out._attachmentBinding).toEqual({
      attached: ['bace_assays.csv'],
      bound: [{ param: 'input_smiles', file: 'bace_assays.csv' }],
      unbound: [],
    });
  });

  it('leaves the literal reference SMILES default alone', async () => {
    const a = assistantReturning(scaffoldHoppingResponse());
    const out = await callGenerate(a, 'train a potency predictor', BACE_MESSAGE);
    expect(out.workflow_ga.optional_params[0].value).toBeUndefined();
    expect(out.workflow_ga.optional_params[0].default).toBe('CC(=O)Nc1ccc(O)cc1');
  });

  it('binds nothing — and records it — when the workflow reads no files', async () => {
    const a = assistantReturning(antibodyComplexResponse());
    const out = await callGenerate(a, 'design nanobody candidates', NANOBODY_MESSAGE);
    expect(out.workflow_ga.inline_parameters).toBeUndefined();
    expect(out._attachmentBinding.bound).toEqual([]);
    expect(out._attachmentBinding.unbound).toEqual([
      '6Z43.pdb', '6Z43.fasta', 'nanobody_candidates.fasta', 'nanobody_constraints.json',
    ]);
  });

  it('binds every modality table to a multi-file input and leaves the truth files out', async () => {
    const bundle = ['rna.csv', 'protein.csv', 'methyl.csv', 'ground_truth.csv', 'true_drivers.csv', 'README.md', 'provenance.json'];
    const message =
      'Integrate the attached multi-omics cohort with SNF.\n\n' +
      `[Attached files: ${bundle.join(', ')}]\n[Uploaded datasets: ` +
      bundle.map((n, i) => `${n}: dataset_id=d${i}, s3_uri=s3://b/d${i}/${n}`).join('; ') + ']';
    const a = assistantReturning({
      success: true,
      workflow_name: 'mofa2',
      workflow_ga: {
        name: 'mofa2',
        required_params: [{ name: 'omics', type: 'file', required: true, default: null, description: 'One features×samples CSV per modality (RNA, proteomics)' }],
        optional_params: [{ name: 'num_factors', type: 'integer', required: false, default: 10, description: 'Number of factors' }],
      },
    });
    const out = await callGenerate(a, 'integrate multi-omics with SNF', message);
    expect(out.workflow_ga.inline_parameters.omics)
      .toBe('s3://b/d0/rna.csv,s3://b/d1/protein.csv,s3://b/d2/methyl.csv');
    // README.md / provenance.json describe the bundle — not data left unused.
    expect(out._attachmentBinding.unbound).toEqual(['ground_truth.csv', 'true_drivers.csv']);
    expect(out._attachmentBinding.attached).not.toContain('README.md');
  });

  it('does nothing when the message carries no attachment', async () => {
    const a = assistantReturning(scaffoldHoppingResponse());
    const out = await callGenerate(a, 'hop the scaffold of aspirin', 'Hop the scaffold of aspirin.');
    expect(out.workflow_ga.required_params[0].value).toBeUndefined();
    expect(out._attachmentBinding).toBeUndefined();
  });

  // Cold-start CSV-orphan regression (2026-11-17): the backend's dataset binder
  // (_bind_uploaded_datasets_to_params) fills the chosen workflow's file param with
  // the uploaded file's s3_uri BEFORE the JS attachment pass runs, so
  // bindAttachmentsToParams skips it as "already bound" and it never appears in
  // _bindings. The report must still count that file as USED (resolvable from a param
  // value) — otherwise the reply says "this workflow does not read your file — use
  // <other> instead" and the panel flags the upload unused, even though it is wired and
  // runnable. This is exactly what happened to the Cox demo (patient_clinical_data.csv →
  // survival_cox…) and the differentialabundance demo (counts/metadata/contrasts).
  it('counts a file the backend already wired to a param value as bound, not unused', async () => {
    const COX_URI = 's3://biomate-nextflow-work/uploads/25d12a93/patient_clinical_data.csv';
    const message =
      'Run survival_cox_proportional_hazards_regression on the attached autoimmune-cohort clinical data.\n\n' +
      '[Attached files: patient_clinical_data.csv]\n' +
      `[Uploaded datasets: patient_clinical_data.csv: dataset_id=25d12a93, s3_uri=${COX_URI}]`;
    const a = assistantReturning({
      success: true,
      workflow_name: 'Survival Cox Proportional Hazards Regression',
      workflow_ga: {
        name: 'survival_cox_proportional_hazards_regression',
        // Executor-owned file input surfaced as an optional_param already carrying the
        // uploaded s3_uri (the real delivered shape — see docs/ cold-start audit).
        required_params: [],
        optional_params: [
          {
            name: 'patient_clinical_data', label: 'Patient Clinical Data', type: 'file',
            data_input: true, autoFilled: true,
            description: 'Data input file read by the workflow',
            default: COX_URI, value: COX_URI,
          },
        ],
      },
    });
    const out = await callGenerate(a, 'fit a cox model', message);
    expect(out._attachmentBinding.bound).toEqual([
      { param: 'patient_clinical_data', file: 'patient_clinical_data.csv' },
    ]);
    expect(out._attachmentBinding.unbound).toEqual([]);
    expect(out._attachmentBinding.attached).toEqual(['patient_clinical_data.csv']);
  });
});

describe('attachmentBoundParams — the bound values the chat response carries', () => {
  it('returns what the binding filled, so the clarification for it can be withdrawn', async () => {
    const a = assistantReturning(scaffoldHoppingResponse());
    const out = await callGenerate(a, 'train a potency predictor', BACE_MESSAGE);
    expect(attachmentBoundParams(out)).toEqual({ input_smiles: BACE_URI });
  });

  it('is empty when nothing was bound', async () => {
    const a = assistantReturning(antibodyComplexResponse());
    const out = await callGenerate(a, 'design nanobody candidates', NANOBODY_MESSAGE);
    expect(attachmentBoundParams(out)).toEqual({});
    expect(attachmentBoundParams(undefined)).toEqual({});
  });
});

describe('groundInlineParameters — a bare file name as a parameter value', () => {
  it('drops it when the parameter takes inline content', async () => {
    const r = await groundInlineParameters({
      workflowName: 'Antibody Antigen Complex',
      rawParams: { antibodies: 'nanobody_candidates.fasta' },
      userQuery: NANOBODY_MESSAGE,
      requiredParams: [],
      optionalParams: antibodyComplexResponse().workflow_ga.optional_params as any,
    });
    expect(r.params.antibodies).toBeUndefined();
  });

  it('rewrites it to the dataset reference when the parameter takes a file', async () => {
    const r = await groundInlineParameters({
      workflowName: 'Scaffold Hopping',
      rawParams: { input_smiles: 'bace_assays.csv' },
      userQuery: BACE_MESSAGE,
      requiredParams: scaffoldHoppingResponse().workflow_ga.required_params as any,
      optionalParams: scaffoldHoppingResponse().workflow_ga.optional_params as any,
    });
    expect(r.params.input_smiles).toBe(BACE_URI);
  });
});
