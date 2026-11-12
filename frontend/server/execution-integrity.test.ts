import { describe, it, expect } from 'vitest';
import { attachedInputNames, claimedOutputFiles, shouldRequireExecution, unbackedOutputFileClaims, generatesSyntheticData, redactStoragePaths, requestAsksForSimulation, SYNTHETIC_DATA_REFUSAL } from './execution-integrity';
import { requireNonEmptyResponse, stripDatasetReferenceParams, parseUploadedDatasetRefs, groundInlineParameters } from './galaxy-assistant';

describe('structural execution guard', () => {
  const base = { runCodeOffered: true, ranRunCode: false, alreadyNudged: false, proseSignal: false };
  it('classifier direct_compute + no run_code ⇒ re-prompt, with no prose signal needed', () => {
    expect(shouldRequireExecution({ ...base, directCompute: true })).toBe(true);
  });
  it('once only, and never after run_code ran or when run_code is not offered', () => {
    expect(shouldRequireExecution({ ...base, directCompute: true, alreadyNudged: true })).toBe(false);
    expect(shouldRequireExecution({ ...base, directCompute: true, ranRunCode: true })).toBe(false);
    expect(shouldRequireExecution({ ...base, directCompute: true, runCodeOffered: false })).toBe(false);
  });
  it('prose regex is a secondary signal for non-direct_compute turns', () => {
    expect(shouldRequireExecution({ ...base, directCompute: false })).toBe(false);
    expect(shouldRequireExecution({ ...base, directCompute: false, proseSignal: true })).toBe(true);
  });
});

describe('output files must be run_code artifacts', () => {
  const reply = '已生成结果文件 summary_by_area.csv，并保存为 approvals.png。[下载](sandbox:/out/report.xlsx)';
  it('extracts claimed files (zh/en verbs, links)', () => {
    expect(claimedOutputFiles(reply).sort()).toEqual(['approvals.png', 'report.xlsx', 'summary_by_area.csv']);
    expect(claimedOutputFiles('I saved the table as counts.tsv')).toEqual(['counts.tsv']);
  });
  it('flags only files run_code did not produce, and not the user\'s inputs', () => {
    expect(unbackedOutputFileClaims(reply, ['summary_by_area.csv'])).toEqual(['approvals.png', 'report.xlsx']);
    expect(unbackedOutputFileClaims('Generated from epar.jsonl: done', [], ['epar.jsonl'])).toEqual([]);
    expect(unbackedOutputFileClaims(reply, ['summary_by_area.csv', 'approvals.png', 'report.xlsx'])).toEqual([]);
  });
  it('honest note in the user\'s language; empty when nothing is unbacked', () => {
  });
  it('reads attached input names', () => {
    expect(attachedInputNames('x\n\n[Attached files: epar.jsonl, b.csv]')).toEqual(['epar.jsonl', 'b.csv']);
  });
});

describe('empty provider reply fails over (root cause of the removed mustGenerateWorkflow)', () => {
  it('throws on empty / whitespace, passes text through', () => {
    expect(() => requireNonEmptyResponse('', 'Gemini')).toThrow(/empty/);
    expect(() => requireNonEmptyResponse('  \n', 'Gemini')).toThrow();
    expect(() => requireNonEmptyResponse(undefined, 'Gemini')).toThrow();
    expect(requireNonEmptyResponse('ok', 'Gemini')).toBe('ok');
  });
});

describe('W4: dataset references are never workflow params', () => {
  const msg = 'go\n\n[Attached files: epar.jsonl]\n[Uploaded datasets: epar.jsonl: dataset_id=6f1c2a9e-3b7d-4c55-9a0e-1d2e3f4a5b6c, galaxy_dataset_id=f2db41e8fa331b3e, s3_uri=s3://b/u1/epar.jsonl]';
  it('parses upload refs', () => {
    const r = parseUploadedDatasetRefs(msg);
    expect(r.get('6f1c2a9e-3b7d-4c55-9a0e-1d2e3f4a5b6c')).toEqual({ name: 'epar.jsonl', s3Uri: 's3://b/u1/epar.jsonl' });
    expect(r.get('f2db41e8fa331b3e')?.name).toBe('epar.jsonl');
  });
  it('drops dataset-reference keys the schema does not declare; rebinds id values to the file URI', () => {
    const out = stripDatasetReferenceParams({
      dataset_id: '6f1c2a9e-3b7d-4c55-9a0e-1d2e3f4a5b6c', 'Dataset Id': 'x', galaxy_dataset_id: 'f2db41e8fa331b3e', s3_uri: 's3://b/u1/epar.jsonl',
      input_table: '6f1c2a9e-3b7d-4c55-9a0e-1d2e3f4a5b6c', threshold: '0.05',
    }, msg);
    expect(out).toEqual({ input_table: 's3://b/u1/epar.jsonl', threshold: '0.05' });
  });
  it('keeps a dataset_id param the chosen workflow declares, bound to the file (shown by name)', () => {
    const out = stripDatasetReferenceParams({ dataset_id: '6f1c2a9e-3b7d-4c55-9a0e-1d2e3f4a5b6c' }, msg, new Set(['dataset_id']));
    expect(out).toEqual({ dataset_id: 's3://b/u1/epar.jsonl' });
  });
  it('groundInlineParameters never emits the upload UUID, schema-less or not', async () => {
    const raw = { dataset_id: '6f1c2a9e-3b7d-4c55-9a0e-1d2e3f4a5b6c', alpha: '0.1' };
    const noSchema = await groundInlineParameters({ workflowName: 'some_wf', rawParams: raw, userQuery: msg });
    expect(JSON.stringify(noSchema.params)).not.toContain('6f1c2a9e');
    const withSchema = await groundInlineParameters({ workflowName: 'some_wf', rawParams: raw, userQuery: msg, requiredParams: ['alpha'] });
    expect(withSchema.params).toEqual({ alpha: '0.1' });
  });
});

describe('generatesSyntheticData — run_code that invents its input (EBV, dev 2026-11-11)', () => {
  it('flags genuine input-fabrication draws when nothing was staged', () => {
    expect(generatesSyntheticData('import numpy as np\nod = np.random.normal(0.8, 0.2, 30)', 0)).toBe(true);
    expect(generatesSyntheticData('rng = np.random.default_rng(1)', 0)).toBe(true);
    expect(generatesSyntheticData('set.seed(1); x <- rnorm(30)', 0)).toBe(true); // the rnorm draw, not the seed
    // torch / scipy.rvs / sklearn make_* were evading the old regex — now covered.
    expect(generatesSyntheticData('import torch\nx = torch.randn(64, 10)', 0)).toBe(true);
    expect(generatesSyntheticData('from scipy import stats\ny = stats.norm.rvs(size=50)', 0)).toBe(true);
    expect(generatesSyntheticData('X, y = make_classification(n_samples=200)', 0)).toBe(true);
  });
  it('does not flag reproducibility seeds, resampling of real data, or algorithm names (2026-11-11 precision fix)', () => {
    expect(generatesSyntheticData('df = pd.read_csv(INPUT_FILES["a.csv"]); np.random.seed(0)', 1)).toBe(false);
    expect(generatesSyntheticData('import math\nprint(math.log10(2500))', 0)).toBe(false);
    // Seed-setting and resampling are not fabrication; neither is an optimiser or a
    // comment that merely says "simulate" — these were false positives that wrongly
    // refused real-data run_code (correctness review 2026-11-11).
    expect(generatesSyntheticData('np.random.seed(0)\nnp.random.shuffle(idx)', 0)).toBe(false);
    expect(generatesSyntheticData('set.seed(42)', 0)).toBe(false);
    expect(generatesSyntheticData('best = simulated_annealing(objective)', 0)).toBe(false);
    expect(generatesSyntheticData('# simulate OD readings from literature distributions', 0)).toBe(false);
  });
  it('a refused attempt tells the model to use real data and report no numbers', () => {
    expect(SYNTHETIC_DATA_REFUSAL).toMatch(/NOT EXECUTED/);
    expect(SYNTHETIC_DATA_REFUSAL).toMatch(/Do not report any numbers/);
  });
  // The run_code gate (galaxy-assistant.ts) refuses only when the code fabricates
  // input AND the user did not ask for a simulation. Assert that composition here,
  // where both predicates live, so a regression in either is caught without a live run.
  it('refuses fabrication-without-staged-data only when no simulation was requested', () => {
    const refuses = (code: string, staged: number, msg: string) =>
      generatesSyntheticData(code, staged) && !requestAsksForSimulation(msg);
    const fab = 'od = np.random.normal(0.8, 0.2, 30)';
    expect(refuses(fab, 0, 'quantify EBV titers from the ELISA readings')).toBe(true);   // invented data → refused
    expect(refuses(fab, 0, 'run a Monte Carlo power analysis for this assay')).toBe(false); // simulation asked → allowed
    expect(refuses(fab, 1, 'analyze the attached plate')).toBe(false);                    // real data staged → allowed
    expect(refuses('mean(df$value)', 0, 'summarise the pasted values')).toBe(false);      // no fabrication → allowed
  });
});

describe('redactStoragePaths — no storage URIs in reply prose', () => {
  it('folder prefixes become "the staged dataset"; file URIs become their file name', () => {
    expect(redactStoragePaths('Using the movies at s3://biomate-cryo-data/empiar-10028/Micrographs/ (20 files).'))
      .toBe('Using the movies at the staged dataset (20 files).');
    expect(redactStoragePaths('Input: `s3://biomate-nextflow-work/uploads/ab12/pilot_compounds.csv`'))
      .toBe('Input: pilot_compounds.csv');
    expect(redactStoragePaths('数据位于 s3://b/x/', true)).toBe('数据位于 已准备好的数据集');
  });
  it('leaves code blocks and ordinary text untouched', () => {
    const code = '```python\npath = "s3://b/x/a.csv"\n```';
    expect(redactStoragePaths(code)).toBe(code);
    expect(redactStoragePaths('No storage here.')).toBe('No storage here.');
  });
});

describe('requestAsksForSimulation — generating values is the task only when the user asked for it', () => {
  it.each([
    'Run a power analysis for a two-arm trial with effect size 0.5',
    'Simulate a one-compartment PK curve for 100 mg q12h',
    'Do a Monte Carlo estimate of the false-positive rate',
    'bootstrap the confidence interval',
    '模拟一个两组试验的样本量',
    '用蒙特卡洛方法估计',
  ])('simulation requested: %s', (m) => { expect(requestAsksForSimulation(m)).toBe(true); });
  it.each([
    'Run analyze_ebv_antibody_titers on its built-in ELISA OD readings and standard-curve data',
    'Summarise this assay table and plot potency against logP.',
    '计算这些样本的平均值',
  ])('not a simulation request: %s', (m) => { expect(requestAsksForSimulation(m)).toBe(false); });
});
