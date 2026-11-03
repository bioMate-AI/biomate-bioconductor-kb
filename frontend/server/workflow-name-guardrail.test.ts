import { describe, expect, it } from 'vitest';
import { textWorkflowName, workflowSlug } from './galaxy-assistant';

// Response headers captured from dev on 2026-11-03 (cold-start routing baseline). Step 6c-2
// reads the workflow a response presents from its header and moves the card to it, so the
// extractor must find real workflow names and must NOT treat bold prose as one.
describe('textWorkflowName — the workflow a response presents', () => {
  it.each([
    ["I'll help you summarize the BACE1 assay data.  **hts_plate_qc_hit_calling** — Automated assay data ingestion", 'hts_plate_qc_hit_calling'],
    ['**reinvent4_lead_design** — AI-driven generative design with multi-objective optimization', 'reinvent4_lead_design'],
    ['**perform_chipseq_peak_calling_with_macs2** — ChIP-seq peak calling for transcription factor', 'perform_chipseq_peak_calling_with_macs2'],
    ['**IC50 Correlation Analysis** — Compare predicted vs. measured IC50 values', 'IC50 Correlation Analysis'],
    ['**REINVENT4 Generative Lead Design** — generative design', 'REINVENT4 Generative Lead Design'],
    ['**Predict ADMET Properties (AI)** — ADMET prediction', 'Predict ADMET Properties (AI)'],
  ])('%s', (text, expected) => {
    expect(textWorkflowName(text)).toBe(expected);
  });

  it.each([
    // nf-core names belong to the dedicated nf-core guardrail
    '**nf-core/differentialabundance** — DESeq2 differential expression with paired-sample design',
    // bold prose / labels are not workflow names
    '## Evidence Linking ABL1  **The BCR-ABL1 fusion is the molecular hallmark and principal driver of CML**',
    'I need to clarify a limitation here.  **BioMate does not currently ship a built-in "human_cachexia" demo dataset**',
    '- **Input:** Your RNA-seq FASTQ files',
    'No bold header at all.',
  ])('not a workflow name: %s', text => {
    expect(textWorkflowName(text)).toBeNull();
  });
});

describe('workflowSlug — one identity for display names and ids', () => {
  it('maps the display name and the snake_case id of a workflow to the same slug', () => {
    expect(workflowSlug('Perform Chipseq Peak Calling With Macs2')).toBe('perform_chipseq_peak_calling_with_macs2');
    expect(workflowSlug('perform_chipseq_peak_calling_with_macs2')).toBe('perform_chipseq_peak_calling_with_macs2');
    expect(workflowSlug('Predict ADMET Properties (AI)')).toBe('predict_admet_properties_ai');
    expect(workflowSlug('')).toBe('');
  });
});
