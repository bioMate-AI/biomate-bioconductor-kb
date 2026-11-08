import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { isSimpleSequencePropertyRequest } from './sequence-property-intent';

const sequence = 'ACDEFGHIKLMNPQRSTVWY';
describe('simple sequence property execution', () => {
  it.each([
    `Calculate the physicochemical properties, molecular weight and isoelectric point of peptide sequence ${sequence}.`,
    `Compute molecular weight and pI for protein ${sequence}`,
    `计算肽序列的分子量和等电点：${sequence}`,
  ])('uses direct execution for a basic calculation: %s', request => {
    expect(isSimpleSequencePropertyRequest(request)).toBe(true);
  });
  it.each([
    'What is the isoelectric point of a peptide?',
    `Predict the structure and molecular weight of peptide ${sequence}`,
    `Design cyclic peptides with low molecular weight against ${sequence}`,
    `Calculate molecular weight of modified peptide ${sequence}`,
    `Calculate molecular weight of cyclic peptide ${sequence}`,
    `Run a Nextflow workflow to calculate molecular weight of ${sequence}`,
    `Compute docking affinity and molecular weight of peptide ${sequence}`,
    `Calculate molecular weight for nucleotide sequence ACGTACGTACGTACGT`,
    `Compare the protein sequences ${sequence}`,
    `计算环肽的分子量：${sequence}`,
  ])('does not hijack a different task: %s', request => {
    expect(isSimpleSequencePropertyRequest(request)).toBe(false);
  });
  it('wires the same predicate to routing and actual execution instructions', () => {
    const source = readFileSync('server/galaxy-assistant.ts', 'utf8');
    expect(source).toContain('|| isSimpleSequencePropertyRequest(message)');
    expect(source).toContain('if (isSimpleSequencePropertyRequest(message))');
    expect(source).toContain('molecular_weight and isoelectric_point');
    expect(source).toContain('below 40 predicted stable and above 40 potentially unstable');
    expect(source).toContain('not a measured half-life or a validated stability threshold for this short peptide');
  });
});
