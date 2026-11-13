import { describe, expect, it } from 'vitest';
import {
  isDataInputParam,
  isOptionalFileOverride,
  unboundRequiredDataInputs,
  messageCarriesRunData,
  messageWaivesDataAsk,
  workflowHasExampleData,
  exampleDataNote,
  shouldRunOnExampleData,
} from './workflow-data-inputs';
import { decideWorkflowReplyState } from './workflow-response-state';

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
  it('blocks unbound clinic-hard data even when schema left it optional (cryo / DE stubs)', () => {
    const cryo = {
      optional_params: [
        { name: 'movies_path', type: 'string', format: 'file-path', required: false, default: null },
        { name: 'gain_ref', type: 'file', required: false, default: null },
      ],
      required_params: [],
    };
    expect(unboundRequiredDataInputs({ workflow_ga: cryo }).map(i => i.name)).toEqual(['movies_path']);
    const de = {
      optional_params: [
        { name: 'samplesheet', type: 'string', format: 'file-path', required: false },
        { name: 'matrix', type: 'string', format: 'file-path', required: false },
        { name: 'contrasts', type: 'string', format: 'file-path', required: false },
      ],
      required_params: [],
    };
    expect(unboundRequiredDataInputs({ workflow_ga: de }).map(i => i.name).sort()).toEqual([
      'matrix',
      'samplesheet',
    ]);
  });
});

describe('isDataInputParam — clinic hard primary', () => {
  it('treats movies_path as a data input even when required=false', () => {
    expect(isDataInputParam({ name: 'movies_path', type: 'string', required: false })).toBe(true);
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

// ── Example-data default (docs/20261111) ─────────────────────────────────────
// A workflow that ships its own bundled example dataset runs with no user input.
// Shapes below are the REAL generated cards captured from dev (85014ef9) for the
// cold-start example workflows; the backend adds `example_data` after this fix.
describe('example-data default: card runs on its own dataset without asking', () => {
  // Mirrors the inline decision in server/galaxy-assistant.ts (the two signals the
  // fix changes): runsOnExampleData and needsDataInput.
  const decide = (gw: any, message: string) => {
    const runnableWorkflow = !!(gw && gw.success);
    const unbound = unboundRequiredDataInputs(gw, new Set<string>());
    const userSuppliedRunData = messageCarriesRunData(message) || messageWaivesDataAsk(message);
    const runsOnExampleData = shouldRunOnExampleData(gw, { runnableWorkflow, userSuppliedRunData });
    const state = decideWorkflowReplyState({
      isWorkflowTurn: true, runnableWorkflow, generationFailed: false, hasInlineData: false,
      messageCarriesData: userSuppliedRunData || runsOnExampleData, unboundRequiredInputs: unbound,
    });
    return { runsOnExampleData, needsDataInput: state === 'generated_needs_input' && !runsOnExampleData, state };
  };

  // Real dev shape: Chemoproteomics Pulldown (input_file type:file, required:null).
  const chemo = (withExampleData: boolean) => ({
    success: true,
    workflow_ga: {
      name: 'Chemoproteomics Pulldown',
      required_params: [{ name: 'input_file', type: 'file', required: null, default: null }],
      optional_params: [],
      ...(withExampleData ? { example_data: { present: true, note: "Runs on the workflow's built-in example dataset — attach your own files to replace it." } } : {}),
    },
  });

  // Real dev shape: a required, still-unbound data input (e.g. EBV/metabo-style file param).
  const requiredUnbound = (withExampleData: boolean) => ({
    success: true,
    workflow_ga: {
      name: 'Analyze Ebv Antibody Titers',
      required_params: [{ name: 'raw_od_data', type: 'file', required: true, default: null }],
      optional_params: [],
      ...(withExampleData ? { example_data: { present: true } } : {}),
    },
  });

  const DEMO_FREE = 'Run analyze_ebv_antibody_titers to quantify VCA, EA and EBNA1 titers across the three groups.';

  it('workflowHasExampleData reads the backend flag off the card', () => {
    expect(workflowHasExampleData(chemo(false))).toBe(false);
    expect(workflowHasExampleData(chemo(true))).toBe(true);
    expect(workflowHasExampleData({ example_data: { present: true } })).toBe(true); // top-level too
  });

  it('BEFORE fix: a required data input with no example data and no user data → asks', () => {
    const d = decide(requiredUnbound(false), DEMO_FREE);
    expect(d.runsOnExampleData).toBe(false);
    expect(d.state).toBe('generated_needs_input');
    expect(d.needsDataInput).toBe(true); // the DATA-FIRST ask fires
  });

  it('AFTER fix: the same card carrying example_data → card, no ask, example-data note', () => {
    const d = decide(requiredUnbound(true), DEMO_FREE);
    expect(d.runsOnExampleData).toBe(true);
    expect(d.needsDataInput).toBe(false); // no upload is requested
    expect(exampleDataNote(requiredUnbound(true))).toMatch(/example dataset/i);
    expect(exampleDataNote(requiredUnbound(true))).not.toMatch(/s3:\/\/|\bS3\b/);
  });

  it('chemoproteomics shape flips to example-data runnable once the flag is present', () => {
    expect(decide(chemo(false), DEMO_FREE).runsOnExampleData).toBe(false);
    expect(decide(chemo(true), DEMO_FREE).runsOnExampleData).toBe(true);
  });

  it('when the user DID supply data, their data is used — example_data is moot, no false suppression', () => {
    const withAccession = 'Run analyze_ebv_antibody_titers on SRR1039508';
    expect(decide(requiredUnbound(true), withAccession).runsOnExampleData).toBe(false);
  });

  it('a workflow with NO example data still asks when its required input is unbound (DATA-FIRST preserved)', () => {
    expect(decide(requiredUnbound(false), DEMO_FREE).needsDataInput).toBe(true);
  });
});
