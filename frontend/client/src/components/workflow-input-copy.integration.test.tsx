/** Mapped-reference copy through the actual workflow viewer. */
import React from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';
import { NextflowWorkflowViewer } from './nextflow-workflow-viewer';

vi.mock('./chat-output-attachments', () => ({ ChatOutputAttachments: () => null }));
vi.mock('./feedback/report-confusion-button', () => ({ ReportConfusionButton: () => null }));
vi.mock('./feedback/download-outcome-prompt', () => ({ DownloadOutcomePrompt: () => null }));

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn(async () => ({ ok:true,status:200,json:async()=>({}),text:async()=>'' })));
});

function showInputMapping(input: string) {
  const onExecute = vi.fn();
  render(<NextflowWorkflowViewer status="idle" onExecute={onExecute} workflowDefinition={{
    id:'style-a-copy-qa',name:'Style A input display QA',
    steps:{s1:{name:'Process data',tool_id:'owned-tool'}},
    required_params:[{name:'input_csv',label:'Input CSV',type:'string',default:null}],
    optional_params:[{name:'dataset_id',label:'Dataset ID',type:'string',default:null}],
  }} initialParams={{input_csv:input,dataset_id:''}} />);
  fireEvent.click(screen.getByTestId('panel-tab-settings'));
  return {mapping:screen.getByTestId('prerun-inputs-mapped'),onExecute};
}

describe('actual viewer mapped-reference copy', () => {
  it('shows the bound required input as mapped and does not demand another attachment', () => {
    const {mapping,onExecute}=showInputMapping('s3://owned/input/counts.csv');
    expect(within(mapping).getByText('counts.csv')).toBeTruthy();
    expect(within(mapping).getByTestId('prerun-inputs-summary').textContent).toBe('1 mapped');
    expect(within(mapping).getByText('resolved · format not checked')).toBeTruthy();
    // The optional "Dataset ID" string is a setting, not a data input row.
    expect(within(mapping).queryByText('Dataset ID')).toBeNull();
    expect(within(mapping).queryByText(/paperclip/)).toBeNull();
    expect(within(mapping).queryByText(/s3:\/\//)).toBeNull();
    expect(onExecute).not.toHaveBeenCalled();
    expect(screen.getByTestId('panel-tab-settings').textContent).toBe('Workflow settings');
    expect(screen.getByTestId('panel-tab-phases').textContent).toContain('1');
  });

  it('flags the missing required input in the header, keeps attachment guidance, and does not execute', () => {
    const {mapping,onExecute}=showInputMapping('');
    expect(within(mapping).getByTestId('prerun-inputs-summary').textContent).toBe('1 required, not set');
    expect(within(mapping).getByText('required — not set')).toBeTruthy();
    expect(within(mapping).getByText(/paperclip/)).toBeTruthy();
    expect(onExecute).not.toHaveBeenCalled();
    expect(screen.getByTestId('button-run-workflow-panel')).toBeDisabled();
  });
});

describe('nf-core/rnaseq-like pre-run inputs (audit 20261110 §7.3)', () => {
  function showRnaseq() {
    render(<NextflowWorkflowViewer status="idle" onExecute={vi.fn()} workflowDefinition={{
      id:'rnaseq-prerun-qa',name:'nf-core/rnaseq',domain:'transcriptomics',
      steps:{s1:{name:'Alignment',tool_id:'star'}},
      required_params:[{name:'input',type:'string',description:'Samplesheet CSV (sample,fastq_1,fastq_2,strandedness)',default:null}],
      optional_params:[
        {name:'fasta',type:'file',default:null},
        {name:'gtf',type:'file',default:null},
        {name:'gff',type:'file',default:null},
        {name:'gene_bed',type:'file',default:null},
        {name:'transcript_fasta',type:'file',default:null},
        {name:'additional_fasta',type:'file',default:null},
        {name:'splicesites',type:'file',default:null},
        {name:'bbsplit_fasta_list',type:'file',default:null},
        {name:'ribo_database_manifest',type:'file',default:'rrna-db-defaults.txt'},
        {name:'aligner',type:'select',default:'star_salmon',options:[{label:'star_salmon',value:'star_salmon'}]},
      ],
    }} />);
    fireEvent.click(screen.getByTestId('panel-tab-settings'));
    return screen.getByTestId('prerun-inputs-mapped');
  }

  it('lists the required samplesheet first and reports it as not set — never "mapped"', () => {
    const card = showRnaseq();
    const header = within(card).getByTestId('prerun-inputs-header').textContent || '';
    expect(header).toContain('Inputs');
    expect(header).toContain('1 required, not set');
    expect(header).not.toMatch(/mapped/i);
    const rows = within(card).getAllByTestId('prerun-input-row');
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain('Input');
    expect(rows[0].getAttribute('data-status')).toBe('unresolved');
    expect(within(card).getByTestId('prerun-inputs-how-to-provide').textContent).toMatch(/paperclip.*accession/);
    expect(card.textContent).not.toMatch(/\bS3\b|s3:\/\//);
  });

  it('groups the 9 optional reference files collapsed as overrides', () => {
    const card = showRnaseq();
    const overrides = within(card).getByTestId('prerun-input-overrides');
    expect(overrides.tagName).toBe('DETAILS');
    expect((overrides as HTMLDetailsElement).open).toBe(false);
    expect(overrides.textContent).toContain('Reference overrides (9)');
    expect(within(overrides).getAllByTestId('prerun-override-row')).toHaveLength(9);
    expect(within(overrides).getByText('rrna-db-defaults.txt')).toBeTruthy();
    expect(within(overrides).getAllByText('not set — default used')).toHaveLength(8);
  });
});

describe('nf-core/rnaseq as the live catalog sends it: input is executor-owned (data_inputs)', () => {
  // The real dev payload (2026-11-11) has NO `input` param — the executor builds the samplesheet —
  // so the requirement arrives as workflow_ga.data_inputs from the backend schema parser.
  const REFS = ['fasta','gtf','gff','gene_bed','transcript_fasta','additional_fasta','splicesites','bbsplit_fasta_list']
    .map(name => ({ name, type: 'file', required: false, default: null }));
  function show(dataInput: Record<string, unknown>) {
    render(<NextflowWorkflowViewer status="idle" onExecute={vi.fn()} workflowDefinition={{
      id: 'rnaseq-live', name: 'nf-core/rnaseq', domain: 'transcriptomics',
      steps: { s1: { name: 'Alignment', tool_id: 'star' } },
      required_params: [], optional_params: REFS,
      data_inputs: [{ name: 'input', label: 'Samplesheet (sequencing reads)', required: true, executor_bound: true, ...dataInput }],
    } as any} />);
    fireEvent.click(screen.getByTestId('panel-tab-settings'));
    return screen.getByTestId('prerun-inputs-mapped');
  }
  it('shows the samplesheet as the one required input, not set, with no file picker', () => {
    const card = show({ bound: false });
    expect(within(card).getByTestId('prerun-inputs-header').textContent).toContain('1 required, not set');
    const rows = within(card).getAllByTestId('prerun-input-row');
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain('Samplesheet (sequencing reads)');
    expect(rows[0].getAttribute('data-status')).toBe('unresolved');
    expect(within(rows[0]).queryByText('Choose file')).toBeNull();
    expect(card.textContent).not.toMatch(/\bS3\b|s3:\/\//);
  });
  it('shows the accession once the user gave one', () => {
    const card = show({ bound: true, bound_value: 'SRR1039508' });
    const header = within(card).getByTestId('prerun-inputs-header').textContent || '';
    expect(header).not.toContain('required, not set');
    expect(within(card).getAllByTestId('prerun-input-row')[0].textContent).toContain('SRR1039508');
  });
});
