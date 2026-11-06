import { describe, expect, it } from 'vitest';
import { hasComputableData, parseExecutionMode, presentsUnexecutedCode, wantsCodeItself } from './galaxy-assistant';

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
