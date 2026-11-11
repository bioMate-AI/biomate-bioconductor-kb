import { describe, expect, it } from 'vitest';
import { FINAL_ANSWER_INSTRUCTION, claimsProducedOutputFile, conversationHasComputableData, conversationHasPipelineScaleData, finalAnswerRequest, hasComputableData, parseExecutionMode, presentsUnexecutedCode, wantsCodeItself } from './galaxy-assistant';
import { reconcileExecutionMode } from './routing-authority';

// External-user replay on dev (2026-11-04): ad-hoc analysis of the user's own data — a Chinese
// fold-change request on an attached CSV, a cell-viability comparison, DESeq2/clustering on pasted
// tables — got workflow cards (and once a reply that *claimed* to run code). The decision now comes
// from the classifier's language-independent `execution` field, honoured only with data present,
// plus a guard that sends back replies presenting code that never ran.
const ATTACHED = '计算每个基因 control 均值、treated 均值及 fold change\n\n[Attached files: qa.csv]\n'
  + '[Uploaded datasets: qa.csv: dataset_id=u1, galaxy_dataset_id=g1, s3_uri=s3://b/qa.csv]';
const PASTED_COUNTS = 'Run DESeq2 differential expression on this count matrix — 3 ctrl replicates vs 3 treated replicates: '
  + 'gene,ctrl1,ctrl2,ctrl3,treat1,treat2,treat3 GENE1,100,120,110,200,210,190 GENE2,50,55,52,51,49,53 GENE3,300,310,290,100,95,105';
const PASTED_SC = 'Cluster these single-cell RNA-seq counts and generate a UMAP:\nbarcode,CD3D,CD4,CD8A\n'
  + 'AAACCTGAGAAGGCCT,45,32,0\nAAACCTGAGACAGACC,0,0,38\nAAACCTGAGCGTTGCC,1,0,0';
const VCF = 'Annotate and filter these germline variants:\n#CHROM\tPOS\tID\tREF\tALT\n1\t752566\trs3094315\tG\tA\n'
  + '1\t776546\trs12124819\tA\tG\n1\t798959\trs11240777\tG\tA';

describe('hasComputableData', () => {
  it.each([
    ['attached dataset block', ATTACHED],
    ['project dataset block', 'Integrate these [BioMate dataset: ko vs wt.csv (id: a04d)]'],
    ['pasted count matrix (one line)', PASTED_COUNTS],
    ['pasted scRNA counts', PASTED_SC],
    ['pasted VCF excerpt', VCF],
  ])('%s → true', (_n, msg) => expect(hasComputableData(msg)).toBe(true));

  it.each([
    ['knowledge question', 'What is the ADMET profile of imatinib?'],
    ['accession only', 'DEG: tumor vs. normal, GEO accession=GSE22055'],
    ['one comma list in prose', 'Compare EGFR, KRAS, ALK, BRAF and MET in lung adenocarcinoma.'],
  ])('%s → false', (_n, msg) => expect(hasComputableData(msg)).toBe(false));
});

describe('presentsUnexecutedCode', () => {
  it('flags a reply that shows analysis code as if it ran', () => {
    const reply = "Running analysis on `qa_new_account_counts.csv`...\n```python\nimport pandas as pd\n"
      + "df = pd.read_csv('/data/x/qa_new_account_counts.csv', index_col=0)\nprint(df.groupby(level=0).mean())\n```";
    expect(presentsUnexecutedCode(reply)).toBe(true);
  });
  it('ignores short inline snippets and non-code fences', () => {
    expect(presentsUnexecutedCode('Use `pd.read_csv()` to load it.')).toBe(false);
    expect(presentsUnexecutedCode('```\nsome output table\n```')).toBe(false);
  });
});

describe('wantsCodeItself', () => {
  it.each([
    'Write a Python script that computes fold change',
    'give me the R code for DESeq2',
    '帮我写一段代码计算均值',
    '给我一个脚本',
  ])('%s → true', msg => expect(wantsCodeItself(msg)).toBe(true));
  it('a compute request is not a code request', () => {
    expect(wantsCodeItself('请计算两组均值并画图，直接给我结果')).toBe(false);
    expect(wantsCodeItself(PASTED_COUNTS)).toBe(false);
  });
});

describe('parseExecutionMode', () => {
  it('accepts only the two modes', () => {
    expect(parseExecutionMode('direct_compute')).toBe('direct_compute');
    expect(parseExecutionMode('pipeline')).toBe('pipeline');
    expect(parseExecutionMode('run_code')).toBeNull();
    expect(parseExecutionMode(undefined)).toBeNull();
  });
});

// EPAR dataset test on dev (2026-11-10): the dataset block was in the FIRST user turn only; the
// classifier returned execution=direct_compute on "先做第一步" / "第2-5步…" / "不用工作流" (3/3), but a
// current-message-only data check discarded it and generated workflows every time.
describe('conversationHasComputableData', () => {
  const history = [
    { role: 'user', content: 'what this file is for [BioMate dataset: epar_study_tables.jsonl (id: ac170aeb)]' },
    { role: 'assistant', content: '这是 EMA EPAR 临床研究表格……' },
  ];
  it('finds the dataset in an earlier user turn', () => {
    expect(hasComputableData('你可以直接编程统计吗 不用工作流')).toBe(false);
    expect(conversationHasComputableData('你可以直接编程统计吗 不用工作流', { previousMessages: history })).toBe(true);
  });
  it('counts UI-selected datasets', () => {
    expect(conversationHasComputableData('先做第一步', { selectedDatasets: ['ac170aeb'] })).toBe(true);
  });
  it('ignores datasets the assistant merely mentioned', () => {
    expect(conversationHasComputableData('先做第一步', {
      previousMessages: [{ role: 'assistant', content: '[BioMate dataset: x.csv (id: 1)]' }],
    })).toBe(false);
  });
});

describe('claimsProducedOutputFile', () => {
  it.each([
    ['zh claim', '📁 输出文件\n已生成 `clinical_studies_structured.csv`，包含所有提取的字段'],
    ['en claim', 'I saved the summary to summary_stats.json.'],
    ['zh export', '结果已导出为 dosimetry_results.xlsx'],
  ])('%s → true', (_n, t) => {
    expect(claimsProducedOutputFile(t)).toBe(true);
    expect(presentsUnexecutedCode(t)).toBe(true);
  });
  it.each([
    ['mentions the input file', '这个文件 epar_study_tables.jsonl 包含 2,281 条记录'],
    ['asks for a file', 'Please upload a CSV file with your counts.'],
  ])('%s → false', (_n, t) => expect(claimsProducedOutputFile(t)).toBe(false));
});

// Dev 2026-11-11: the classifier (GLM) labelled "Run analyze_ebv_antibody_titers on its built-in …
// sample data" execution=direct_compute in ~2/3 browser turns. With no data in the conversation that
// flipped off workflow generation → no card, and the model told the user to go search the
// Workflows panel. direct_compute needs data to compute on (the classifier's own definition).
describe('direct_compute is honoured only when the conversation has data (reconcileExecutionMode)', () => {
  const EBV = 'Run analyze_ebv_antibody_titers on its built-in ELISA OD readings and standard-curve data; quantify VCA, EA '
    + 'and EBNA1 titers (IgG and IgM) across the EBV-positive, EBV-active and EBV-negative groups using the default sample data.';
  const route = (execution: string, message: string, context: any) => {
    const intent: any = { execution, actions: { needsWorkflowGeneration: true, needsLLMReasoning: false } };
    reconcileExecutionMode(intent, conversationHasComputableData(message, context));
    return intent.actions.needsWorkflowGeneration ? 'workflow card' : 'direct compute';
  };
  it('named workflow on its built-in data, nothing attached → workflow card', () => {
    expect(route('direct_compute', EBV, { previousMessages: [] })).toBe('workflow card');
  });
  it('attached data in this turn → direct compute', () => {
    expect(route('direct_compute', ATTACHED, {})).toBe('direct compute');
  });
  it('data attached in an earlier turn (follow-up) → direct compute', () => {
    expect(route('direct_compute', '先做第一步', { previousMessages: [{ role: 'user', content: ATTACHED }] })).toBe('direct compute');
  });
  it('pipeline label → workflow card', () => {
    expect(route('pipeline', ATTACHED, {})).toBe('workflow card');
  });
});

// Dev 2026-11-11: CRISPR QC spent all 5 agentic turns on run_code; the loop ended with no final text,
// so the user saw only "I'll run a comprehensive QC analysis…" (or a raw "✓ Saved: …png" stdout line).
describe('finalAnswerRequest (tool budget exhausted)', () => {
  const api = { model: 'm', max_tokens: 4096, system: [{ type: 'text', text: 's' }], messages: [{ role: 'user', content: 'orig' }] };
  const tools = [{ name: 'run_code', input_schema: { type: 'object' } }];
  const transcript = [
    { role: 'user', content: 'QC my CRISPR screen' },
    { role: 'assistant', content: [{ type: 'tool_use', id: 't1', name: 'run_code', input: { code: 'print(1)' } }] },
    { role: 'user', content: [{ type: 'tool_result', tool_use_id: 't1', content: '1' }] },
  ];
  it('keeps the transcript, disables tools and asks for the final answer', () => {
    const req = finalAnswerRequest(api, transcript, tools);
    expect(req.tool_choice).toEqual({ type: 'none' });
    expect(req.tools).toBe(tools);
    expect(req.model).toBe('m');
    expect(req.messages).toHaveLength(3);
    const last = req.messages[2].content;
    expect(last[0]).toMatchObject({ type: 'tool_result', tool_use_id: 't1' });
    expect(last[1]).toEqual({ type: 'text', text: FINAL_ANSWER_INSTRUCTION });
    expect(transcript[2].content).toHaveLength(1); // caller's transcript is not mutated
  });
  it('without tools there is no tool_choice', () => {
    const req = finalAnswerRequest(api, [{ role: 'assistant', content: 'x' }], null);
    expect(req.tool_choice).toBeUndefined();
    expect(req.messages.at(-1)).toEqual({ role: 'user', content: FINAL_ANSWER_INSTRUCTION });
  });
});

describe('raw instrument data is pipeline-scale: direct_compute is not honoured (call variants, dev 2026-11-11)', () => {
  const READS = 'Call variants on these samples and flag the clinically relevant ones.\n\n[Attached files: normal_R1.fastq.gz, normal_R2.fastq.gz, reference_grch37.fasta, sequencing_samples.csv]';
  const route = (message: string, context: any = {}) => {
    const intent: any = { execution: 'direct_compute', actions: { needsWorkflowGeneration: true, needsLLMReasoning: false } };
    reconcileExecutionMode(intent, conversationHasComputableData(message, context) && !conversationHasPipelineScaleData(message, context));
    return intent.actions.needsWorkflowGeneration ? 'workflow card' : 'direct compute';
  };
  it('FASTQ attached → workflow card', () => { expect(route(READS)).toBe('workflow card'); });
  it('FASTQ attached in an earlier turn → workflow card', () => {
    expect(route('go ahead', { previousMessages: [{ role: 'user', content: READS }] })).toBe('workflow card');
  });
  it('a table attached → direct compute stays allowed', () => {
    expect(route('Summarise this.\n\n[Attached files: bace_assays.csv]\n[Uploaded datasets: bace_assays.csv: dataset_id=x]')).toBe('direct compute');
  });
  it('a fresh CSV this turn is not blocked by a stale FASTQ from an earlier turn (correctness review 2026-11-11)', () => {
    const ctx = { previousMessages: [{ role: 'user', content: READS }] };
    const freshCsv = "What's the mean of column 3?\n\n[Attached files: counts.csv]\n[Uploaded datasets: counts.csv: dataset_id=y]";
    expect(route(freshCsv, ctx)).toBe('direct compute');
    // …but a follow-up with no data of its own still sees the carried-over FASTQ.
    expect(route('call variants', ctx)).toBe('workflow card');
  });
});
