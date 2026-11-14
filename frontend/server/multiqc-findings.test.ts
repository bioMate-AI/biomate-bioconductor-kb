import { describe, expect, it } from 'vitest';
import { parseMultiqcFindings } from './multiqc-findings';

const MULTIQC = {
  name: 'multiqc_data.json',
  content: JSON.stringify({
    report_general_stats_data: [
      {
        sample_A: {
          percent_aligned: 91.2,
          percent_duplication: 12.4,
          total_sequences: 1_200_000,
        },
        sample_B: {
          percent_aligned: 88.0,
          percent_duplication: 15.1,
          total_sequences: 980_000,
        },
      },
    ],
  }),
};

describe('parseMultiqcFindings', () => {
  it('surfaces mean alignment / duplication as Key Results', () => {
    const f = parseMultiqcFindings([MULTIQC], 'nf-core/rnaseq');
    expect(f).not.toBeNull();
    expect(f!.evidence_version).toBe('multiqc-stats-v1');
    expect(f!.summary).toMatch(/Key QC scores/);
    expect(f!.key_results.some(k => /percent aligned/i.test(k.metric))).toBe(true);
    const aligned = f!.key_results.find(k => /percent aligned/i.test(k.metric))!;
    expect(aligned.value).toMatch(/89\.?6|89\.6/);
  });

  it('returns null when MultiQC has no known score columns', () => {
    expect(parseMultiqcFindings([{
      name: 'multiqc_data.json',
      content: JSON.stringify({ report_general_stats_data: [{ s1: { software_version: '1.0' } }] }),
    }])).toBeNull();
  });
});
