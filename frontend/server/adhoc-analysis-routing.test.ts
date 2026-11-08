import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { isAdhocAnalysisOfAttachedData } from './galaxy-assistant';

// Ad-hoc analysis of ATTACHED data is a run_code task, not a pipeline. Measured 2026-11-04 with the
// exact cold-start UI payloads + real uploads: "Correlate predicted and measured IC50 ..." was forced
// into workflow generation and landed on Run Audit Export / QSAR RF / nf-core/demo.
const PAYLOADS = JSON.parse(readFileSync(resolve(__dirname, '../../evaluation/routing_eval/runs/ui_payloads_20261103.json'), 'utf8'));
const withAttachments = (p: any) => p.files?.length
  ? `${p.prompt}\n\n[Attached files: ${p.files.join(', ')}]\n[Uploaded datasets: ${p.files.map((f: string) => `${f}: dataset_id=x, s3_uri=s3://b/${f}`).join('; ')}]`
  : p.prompt;

describe('isAdhocAnalysisOfAttachedData', () => {
  it('claims exactly the cold-start "Ad-hoc compute" examples among all 106 UI payloads', () => {
    const claimed = PAYLOADS.filter((p: any) => isAdhocAnalysisOfAttachedData(withAttachments(p)));
    expect(claimed.map((p: any) => p.track)).toEqual(['Ad-hoc compute', 'Ad-hoc compute', 'Ad-hoc compute']);
  });

  it.each([
    'Run DESeq2 differential expression on the attached counts, then GO enrichment.',
    'Compute the relative binding free energy between two analogues against my target.',
    'QC my CRISPR screen — guide representation, replicate correlation, and control separation.',
    'Rank these candidates for developability and show me the top 20.',
    'Screen these SMILES for ADMET liabilities and plot the hERG distribution.',
  ])('a workflow request with attached data stays a workflow: %s', goal => {
    expect(isAdhocAnalysisOfAttachedData(`${goal}\n\n[Attached files: a.csv]\n[Uploaded datasets: a.csv: dataset_id=1]`)).toBe(false);
  });

  it('needs attached data: the same ask without an attachment is not claimed', () => {
    expect(isAdhocAnalysisOfAttachedData('Correlate predicted and measured IC50 for these compounds.')).toBe(false);
    expect(isAdhocAnalysisOfAttachedData('Correlate predicted and measured IC50.\n\n[Attached files: p.csv]\n[Uploaded datasets: p.csv: dataset_id=1]')).toBe(true);
  });
});
