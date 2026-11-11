import { describe, expect, it } from 'vitest';
import {
  isDataInputParam,
  isOptionalFileOverride,
  unboundRequiredDataInputs,
  messageCarriesRunData,
  messageWaivesDataAsk,
} from './workflow-data-inputs';

// Shape of nf-core/rnaseq as the panel receives it: the samplesheet `input` is a
// REQUIRED string (stub `params.input = null // Samplesheet CSV …`), while the
// reference overrides are OPTIONAL file params with genome defaults.
const RNASEQ_GA = {
  name: 'nf-core/rnaseq',
  required_params: [
    { name: 'input', type: 'string', description: 'Samplesheet CSV (sample,fastq_1,fastq_2,strandedness)', default: null },
  ],
  optional_params: [
    { name: 'fasta', type: 'file', default: null },
    { name: 'gtf', type: 'file', default: null },
    { name: 'ribo_database_manifest', type: 'file', default: 'rrna-db-defaults.txt' },
    { name: 'aligner', type: 'select', default: 'star_salmon' },
  ],
};

describe('isDataInputParam (schema signals first, names only as fallback)', () => {
  it('treats a required string `input` samplesheet as a data input', () => {
    expect(isDataInputParam({ name: 'input', type: 'string', required: true })).toBe(true);
  });
  it('uses schema signals: required file / file-path format / mimetype / Input group / data_input flag', () => {
    expect(isDataInputParam({ name: 'whatever', type: 'file', required: true })).toBe(true);
    expect(isDataInputParam({ name: 'whatever', type: 'string', format: 'file-path', required: true })).toBe(true);
    expect(isDataInputParam({ name: 'whatever', type: 'string', mimetype: 'text/csv', required: true })).toBe(true);
    expect(isDataInputParam({ name: 'whatever', type: 'string', group: 'Input/output options', required: true })).toBe(true);
    expect(isDataInputParam({ name: 'sce2', type: 'file', required: false, data_input: true })).toBe(true);
  });
  it('never classifies settings, optional overrides or executor-set params as data inputs', () => {
    expect(isDataInputParam({ name: 'genome', type: 'string', required: true })).toBe(false);
    expect(isDataInputParam({ name: 'fasta', type: 'file', required: false })).toBe(false);
    expect(isDataInputParam({ name: 'outdir', type: 'string', group: 'Input/output options', required: true })).toBe(false);
    expect(isDataInputParam({ name: 'email', type: 'string', group: 'Input/output options', required: true })).toBe(false);
  });
  it('identifies optional file overrides', () => {
    expect(isOptionalFileOverride({ name: 'gtf', type: 'file', required: false })).toBe(true);
    expect(isOptionalFileOverride({ name: 'input', type: 'string', required: true })).toBe(false);
    expect(isOptionalFileOverride({ name: 'sce2', type: 'file', required: false, data_input: true })).toBe(false);
  });
});

describe('unboundRequiredDataInputs', () => {
  it('reports the unset samplesheet and ignores the optional reference overrides', () => {
    const got = unboundRequiredDataInputs({ success: true, workflow_ga: RNASEQ_GA });
    expect(got.map(i => i.name)).toEqual(['input']);
    expect(got[0].description).toContain('Samplesheet');
  });
  it('is empty once the input is bound (value, or inline data extracted from the message)', () => {
    const bound = { ...RNASEQ_GA, required_params: [{ ...RNASEQ_GA.required_params[0], value: 'samplesheet.csv' }] };
    expect(unboundRequiredDataInputs({ workflow_ga: bound })).toEqual([]);
    expect(unboundRequiredDataInputs({ workflow_ga: RNASEQ_GA }, new Set(['input']))).toEqual([]);
  });
  it('includes the backend missing_file_inputs list without duplicates', () => {
    const got = unboundRequiredDataInputs({ workflow_ga: RNASEQ_GA, missing_file_inputs: ['input', 'contrasts'] });
    expect(got.map(i => i.name)).toEqual(['input', 'contrasts']);
  });
  it('does not treat a required non-data setting as a missing input', () => {
    expect(unboundRequiredDataInputs({ workflow_ga: { required_params: [{ name: 'genome', type: 'string' }] } })).toEqual([]);
  });
});

describe('message data signals', () => {
  it('detects attached datasets and public accessions', () => {
    expect(messageCarriesRunData('run rnaseq\n[Uploaded datasets: a.fastq.gz: dataset_id=1]')).toBe(true);
    expect(messageCarriesRunData('SRR1039508')).toBe(true);
    expect(messageCarriesRunData('please analyse GSE52778')).toBe(true);
    expect(messageCarriesRunData('用 nf-core/rnaseq 分析我的 RNA-seq 数据')).toBe(false);
  });
  it('detects an explicit request to proceed without data', () => {
    expect(messageWaivesDataAsk('run it with defaults')).toBe(true);
    expect(messageWaivesDataAsk('use the demo data')).toBe(true);
    expect(messageWaivesDataAsk('运行 nf-core/rnaseq')).toBe(false);
  });
});

describe('unboundRequiredDataInputs — executor-owned data_inputs (live rnaseq shape)', () => {
  const live = (bound: boolean) => ({ success: true, workflow_ga: { name: 'nf-core/rnaseq', required_params: [], optional_params: [],
    data_inputs: [{ name: 'input', label: 'Samplesheet (sequencing reads)', required: true, executor_bound: true, bound }] } });
  it('reports the described samplesheet as the unbound required input', () => {
    expect(unboundRequiredDataInputs(live(false)).map(i => i.label)).toEqual(['Samplesheet (sequencing reads)']);
  });
  it('is satisfied when the request carried data (bound)', () => {
    expect(unboundRequiredDataInputs(live(true))).toEqual([]);
  });
});
