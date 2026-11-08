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
  it('does not demand another attachment when one reference is populated and another optional field is empty', () => {
    const {mapping,onExecute}=showInputMapping('s3://owned/input/counts.csv');
    expect(within(mapping).getByText('counts.csv')).toBeTruthy();
    expect(within(mapping).getByText('not set')).toBeTruthy();
    expect(within(mapping).getByText('Input references are set. Review the mapping below.')).toBeTruthy();
    expect(within(mapping).queryByText(/Attach it with the paperclip/)).toBeNull();
    expect(onExecute).not.toHaveBeenCalled();
    expect(screen.getByTestId('panel-tab-settings').textContent).toBe('Workflow settings');
    expect(screen.getByTestId('panel-tab-phases').textContent).toContain('1');
  });

  it('retains attachment guidance when all input references are missing and does not execute', () => {
    const {mapping,onExecute}=showInputMapping('');
    expect(within(mapping).getByText(/Attach it with the paperclip/)).toBeTruthy();
    expect(within(mapping).getAllByText('not set')).toHaveLength(2);
    expect(onExecute).not.toHaveBeenCalled();
    expect(screen.getByTestId('button-run-workflow-panel')).toBeDisabled();
  });
});
