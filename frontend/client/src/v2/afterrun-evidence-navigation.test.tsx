import React from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';
import { AfterRunReport } from './AfterRunReport';

vi.mock('@/components/step-output-preview', () => ({
  StepOutputPreview: ({file}: any) => <div data-testid="actual-requested-output" data-path={file.path}>{file.name}</div>,
}));

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn(async (input: any) => {
    const url = String(input);
    if (url.endsWith('/findings')) return {ok:true,status:200,json:async()=>({
      status:'ok',summary:'The recorded table contains 1102 rows.',
      key_results:[{metric:'Rows',value:'1102',source_file:'sizes.tsv'}],
    })};
    return {ok:false,status:404,json:async()=>({}),text:async()=>''};
  }));
});

const props = {runId:'owned-source-run',workflowName:'Saved table workflow',methodsText:'Recorded method',software:{},citations:[],qcEvents:[]};

describe('findings evidence opens its exact saved artifact', () => {
  it('opens sizes.tsv directly even when it is beyond the output list render cap', async () => {
    const outputs = Array.from({length:55},(_,i)=>({step:'count',name:`other-${i}.tsv`,path:`/saved/other-${i}.tsv`,ext:'tsv'}));
    outputs.push({step:'count',name:'sizes.tsv',path:'/saved/count/sizes.tsv',ext:'tsv'});
    render(<AfterRunReport {...props} outputs={outputs} executionStatus="completed"/>);
    fireEvent.click(await screen.findByTitle('Open source: sizes.tsv'));
    const dialog = await screen.findByRole('dialog',{name:'sizes.tsv'});
    expect(within(dialog).getByTestId('actual-requested-output').getAttribute('data-path')).toBe('/saved/count/sizes.tsv');
    expect(screen.getByTestId('after-tab-outputs').getAttribute('aria-selected')).toBe('true');
    fireEvent.click(within(dialog).getByRole('button',{name:'Close'}));
    fireEvent.click(screen.getByTestId('after-tab-summary'));
    fireEvent.click(await screen.findByTitle('Open source: sizes.tsv'));
    expect(await screen.findByRole('dialog',{name:'sizes.tsv'})).toBeTruthy();
  });

  it('does not guess which artifact a duplicate basename refers to', async () => {
    render(<AfterRunReport {...props} outputs={[
      {step:'one',name:'sizes.tsv',path:'/saved/one/sizes.tsv',ext:'tsv'},
      {step:'two',name:'sizes.tsv',path:'/saved/two/sizes.tsv',ext:'tsv'},
    ]} executionStatus="completed"/>);
    fireEvent.click(await screen.findByTitle('Open source: sizes.tsv'));
    expect(await screen.findByRole('status')).toHaveTextContent('could not be uniquely located');
    expect(screen.queryByRole('dialog')).toBeNull();
  });

  it('uses an exact recorded path to distinguish equal basenames', async () => {
    vi.mocked(fetch).mockImplementation(async (input: any) => ({ok:true,status:200,json:async()=>String(input).endsWith('/findings') ? {
      status:'ok',summary:'The recorded table contains 1102 rows.',
      key_results:[{metric:'Rows',value:'1102',source_file:'/saved/two/sizes.tsv'}],
    } : {},text:async()=>''} as Response));
    render(<AfterRunReport {...props} outputs={[
      {step:'one',name:'sizes.tsv',path:'/saved/one/sizes.tsv',ext:'tsv'},
      {step:'two',name:'sizes.tsv',path:'/saved/two/sizes.tsv',ext:'tsv'},
    ]} executionStatus="completed"/>);
    fireEvent.click(await screen.findByTitle('Open source: /saved/two/sizes.tsv'));
    const dialog=await screen.findByRole('dialog',{name:'sizes.tsv'});
    expect(within(dialog).getByTestId('actual-requested-output').getAttribute('data-path')).toBe('/saved/two/sizes.tsv');
  });

  it('keeps the run record and partial output availability truthful for failed runs', async () => {
    render(<AfterRunReport {...props} outputs={[]} executionStatus="failed"/>);
    expect(screen.getByTestId('afterrun-no-report')).toHaveTextContent('Run incomplete — partial outputs and the run record remain available.');
    expect(screen.queryByText(/No report —/)).toBeNull();
    fireEvent.click(screen.getByTestId('after-tab-report'));
    expect(screen.getByTestId('after-report-doc')).toBeTruthy();
  });
});
