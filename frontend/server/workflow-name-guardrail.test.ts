import { describe, expect, it } from 'vitest';
import { alternativeWorkflowNames, relabelWorkflowHeader, textWorkflowName, workflowSlug } from './galaxy-assistant';

// The only alternatives the response may lead with (and Step 6c-2 may follow): the search's
// other candidates, without the card itself or the catalog's duplicate rows of one workflow.
describe('alternativeWorkflowNames', () => {
  it('excludes the card and same-workflow duplicates, keeps search order, caps at 4', () => {
    expect(alternativeWorkflowNames({
      workflow_ga: { name: 'Assay Ingestion And Ranking' },
      candidate_workflows: [
        { name: 'Assay Ingestion And Ranking' }, { name: 'hts_plate_qc_hit_calling' },
        { name: 'Hts Plate Qc Hit Calling' }, { name: 'REINVENT4 Generative Lead Design' },
        { name: 'Predict ADMET Properties (AI)' }, { name: 'Qsar Rf Model' }, { name: 'drugclip' },
      ],
    })).toEqual(['hts_plate_qc_hit_calling', 'REINVENT4 Generative Lead Design', 'Predict ADMET Properties (AI)', 'Qsar Rf Model']);
    expect(alternativeWorkflowNames({ workflow_ga: { name: 'x' } })).toEqual([]);
    expect(alternativeWorkflowNames(null)).toEqual([]);
  });
});
import { cardWorkflowName } from './workflow-display-name';

// The chat response is told this exact name, and the card shows it (routes.ts workflow_ready).
describe('cardWorkflowName — the title the workflow card shows', () => {
  it('follows the card resolution order and humanizes slugs the same way', () => {
    expect(cardWorkflowName({ workflow_ga: { name: 'hts_plate_qc_hit_calling' }, workflow_name: 'x' })).toBe('Hts Plate Qc Hit Calling');
    expect(cardWorkflowName({ workflow_ga: {}, workflow_name: 'Qsar Rf Model' })).toBe('Qsar Rf Model');
    expect(cardWorkflowName({ chain_display_name: 'GEO → limma' })).toBe('GEO → limma');
    expect(cardWorkflowName({ workflow_ga: { name: 'cyclic_peptide_design' } })).toBe('Cyclic Peptide Design');
    expect(cardWorkflowName({})).toBe('');
    expect(cardWorkflowName(null)).toBe('');
  });
});

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

// Dev 2026-11-11 (founder screenshot): "Design nanobody candidates against this epitope." answered
// "**Nanobody Fusion Design** — …" / "**Nanobody Design Against SARS-CoV-2 Spike RBD** — …" over a
// `bispecific_antibody_design` card. An invented title is never one of the search candidates, so
// Step 6c-2 kept the card (correctly) and left the reply naming a workflow that does not exist.
// CLAUDE.md: the chat name must be the card title exactly, so the header is relabelled in place.
describe('relabelWorkflowHeader — the reply adopts the card name when its own name is invented', () => {
  it('rewrites the header and keeps the one-line description', () => {
    const text = '**Nanobody Design Against SARS-CoV-2 Spike RBD** — Structure-guided epitope mapping.\n\n- **Input:** 6Z43.pdb';
    expect(relabelWorkflowHeader(text, 'Nanobody Design Against SARS-CoV-2 Spike RBD', 'Bispecific Antibody Design'))
      .toBe('**Bispecific Antibody Design** — Structure-guided epitope mapping.\n\n- **Input:** 6Z43.pdb');
  });

  it('leaves the body alone and only touches the first bold span', () => {
    const text = '**Nanobody Fusion Design** — 针对 SARS-CoV-2 Spike RBD 表位的纳米抗体候选设计\n- **Input:** 6Z43.pdb';
    expect(relabelWorkflowHeader(text, 'Nanobody Fusion Design', 'Bispecific Antibody Design'))
      .toBe('**Bispecific Antibody Design** — 针对 SARS-CoV-2 Spike RBD 表位的纳米抗体候选设计\n- **Input:** 6Z43.pdb');
  });

  it('is a no-op when the header already is the card, when it is some other span, or when inputs are missing', () => {
    const same = '**Bispecific Antibody Design** — two-arm construct';
    expect(relabelWorkflowHeader(same, 'bispecific_antibody_design', 'Bispecific Antibody Design')).toBe(same);
    const moved = '- **Input:** Your FASTA\n**Qsar Rf Model** — train a model';
    expect(relabelWorkflowHeader(moved, 'Qsar Rf Model', 'Scaffold Hopping')).toBe(moved);
    expect(relabelWorkflowHeader('no bold here', 'X', 'Y')).toBe('no bold here');
    expect(relabelWorkflowHeader('**X** — y', '', 'Y')).toBe('**X** — y');
    expect(relabelWorkflowHeader('**X** — y', 'X', '')).toBe('**X** — y');
  });
});
