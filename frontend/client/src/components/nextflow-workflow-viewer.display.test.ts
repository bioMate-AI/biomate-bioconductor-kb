import { describe, expect, it } from 'vitest';
import { cleanParamValueForDisplay, userFacingStepName } from './nextflow-workflow-viewer';

// Real values from the live dev phase tab (2026-11-11): storage paths and UUIDs
// must never reach the user — the file is shown by its name.
describe('cleanParamValueForDisplay — filename, never a storage path or UUID', () => {
  it.each([
    ['s3://biomate-nextflow-work/uploads/0238d454-8be2-42db-9bc7-9e76e274f317/sample_metadata.csv', 'sample_metadata.csv'],
    ['s3://biomate-nextflow-work/uploads/5126c5f4-b910-4c78-9577-413fe4ea88bc/counts_matrix.csv', 'counts_matrix.csv'],
    ['contrasts.csv (id: b7167030-2ad6-4419-9ccc-6eb00968e2fc)', 'contrasts.csv'],
    ['/data/run/reads_R1.fastq.gz', 'reads_R1.fastq.gz'],
    ['https://ftp.ebi.ac.uk/pub/databases/emdb/structures/EMD-5995/map/emd_5995.map.gz', 'emd_5995.map.gz'],
    ['s3://biomate-cryo-data/empiar-10028/Micrographs/', ''],
  ])('%s → %s', (raw, want) => { expect(cleanParamValueForDisplay(raw)).toBe(want); });
  it.each(['2', '0.05', 'rnaseq', 'GRCh38', 'treated_vs_control', 'g4s3'])('leaves plain values alone: %s', (v) => {
    expect(cleanParamValueForDisplay(v)).toBe(v);
  });
});

describe('userFacingStepName — names the work, not the infrastructure', () => {
  it.each([
    ['Download samplesheet and count matrix from S3', 'Download samplesheet and count matrix'],
    ['Upload results to the S3 bucket', 'Upload results'],
    ['Align reads on AWS Batch', 'Align reads'],
    ['Run DESeq2 per contrast', 'Run DESeq2 per contrast'],
    ['PCA, volcano, MA plots + HTML report', 'PCA, volcano, MA plots + HTML report'],
  ])('%s → %s', (raw, want) => { expect(userFacingStepName(raw)).toBe(want); });
});
