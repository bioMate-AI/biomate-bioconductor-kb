import { describe, it, expect } from 'vitest';
import { userFacingErrorText } from './user-facing-error';
import { classifyRunFailure, formatRunFailureReply } from './run-failure-classifier';

describe('userFacingErrorText — run errors as the user reads them', () => {
  it('no storage URIs, upload ids or infrastructure names', () => {
    const raw = 'Process DESEQ2 failed; AWS Batch job exited. Input s3://biomate-uploads/3f2b1c9a-1111-2222-3333-444455556666/counts.csv not found in S3 bucket; Galaxy dataset missing\n  at nextflow.cli.Launcher.main(Launcher.groovy:675)';
    const out = userFacingErrorText(raw);
    expect(out).not.toMatch(/s3:\/\/|\bS3\b|AWS|Batch|Galaxy|biomate-uploads|3f2b1c9a|Launcher/i);
    expect(out).toContain('counts.csv');
  });
  it('a folder URI becomes neutral words, not the bucket', () => {
    expect(userFacingErrorText('workDir: s3://biomate-nextflow-work/nextflow/work/u1/r9/')).toBe('workDir: the stored data');
  });
  it('redacts cryo seed-bucket names even without a full URI', () => {
    expect(userFacingErrorText('missing prefix biomate-cryo-data/empiar-10028')).toMatch(/storage/);
    expect(userFacingErrorText('missing prefix biomate-cryo-data/empiar-10028')).not.toMatch(/biomate-cryo-data/);
  });
});

describe('run-failure reply names files, not storage paths', () => {
  it('missing-file explanation uses the file name only', () => {
    const exp = classifyRunFailure("No such file: 's3://biomate-uploads/3f2b1c9a-1111-2222-3333-444455556666/sample_sheet.csv'");
    const reply = formatRunFailureReply(exp);
    expect(reply).not.toMatch(/s3:|\/\/|biomate-uploads|3f2b1c9a/);
  });
});
