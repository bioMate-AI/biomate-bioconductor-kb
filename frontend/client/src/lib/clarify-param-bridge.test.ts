/**
 * Founder report (2026-11-11, parameterFillNotWorking.png): with bace_assays.csv
 * attached, the "Which input_smiles?" card was answered "use the attached file"
 * and "Confirm and configure" did not bind anything — the panel still showed the
 * required input as unset, because the bridge wrote the sentence into the param.
 */
import { describe, it, expect } from 'vitest';
import { applyClarificationAnswer, paramSpec } from './clarify-param-bridge';

const URI = 's3://biomate-nextflow-work/uploads/78ff4255/bace_assays.csv';

const messages = [
  {
    role: 'user',
    content:
      'Train a potency predictor on our in-house assay data.\n\n' +
      '[Attached files: bace_assays.csv]\n' +
      `[Uploaded datasets: bace_assays.csv: dataset_id=78ff4255, galaxy_dataset_id=dbc5108, s3_uri=${URI}]`,
  },
  { role: 'assistant', content: 'Scaffold Hopping — 1 required parameter needs to be filled.' },
];

const workflow = {
  name: 'Scaffold Hopping',
  required_params: [
    { name: 'input_smiles', type: 'string', required: true, description: 'path to SMILES file (one "SMILES compound_id" per line)' },
  ],
  optional_params: [
    { name: 'reference_smiles', type: 'string', required: false, default: 'CC(=O)Nc1ccc(O)cc1', description: 'acetaminophen as default reference' },
  ],
};

describe('applyClarificationAnswer', () => {
  it('binds the attached file, not the words the user typed', () => {
    const r = applyClarificationAnswer(workflow, { paramName: 'input_smiles', value: 'use the attached file' }, messages);
    expect(r.value).toBe(URI);
    expect(r.file?.name).toBe('bace_assays.csv');
    expect(r.workflow.inline_parameters.input_smiles).toBe(URI);
  });

  it('binds for the Chinese phrasing and for the file name', () => {
    for (const answer of ['用附件', 'bace_assays.csv']) {
      expect(applyClarificationAnswer(workflow, { paramName: 'input_smiles', value: answer }, messages).value).toBe(URI);
    }
  });

  it('keeps a real value as typed', () => {
    const r = applyClarificationAnswer(workflow, { paramName: 'reference_smiles', value: 'CCO' }, messages);
    expect(r.value).toBe('CCO');
    expect(r.file).toBeUndefined();
    expect(r.workflow.inline_parameters.reference_smiles).toBe('CCO');
  });

  it('keeps the answer when nothing was attached in the conversation', () => {
    const r = applyClarificationAnswer(workflow, { paramName: 'input_smiles', value: 'use the attached file' }, []);
    expect(r.value).toBe('use the attached file');
  });

  it('preserves params already bound on the panel workflow', () => {
    const withParams = { ...workflow, inline_parameters: { max_candidates: '20' } };
    const r = applyClarificationAnswer(withParams, { paramName: 'input_smiles', value: '用附件' }, messages);
    expect(r.workflow.inline_parameters).toEqual({ max_candidates: '20', input_smiles: URI });
  });

  it('is a no-op without a workflow or a param name', () => {
    expect(applyClarificationAnswer(null, { paramName: 'input_smiles', value: 'x' }, messages).workflow).toBeNull();
    expect(applyClarificationAnswer(workflow, { paramName: '', value: 'x' }, messages).workflow).toBe(workflow);
  });

  it('finds the parameter definition the answer targets', () => {
    expect(paramSpec(workflow, 'input_smiles')?.required).toBe(true);
    expect(paramSpec(workflow, 'nope')).toBeUndefined();
  });
});
