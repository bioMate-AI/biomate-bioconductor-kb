import React from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { NextflowWorkflowViewer, failureDiagnosisMessage } from './nextflow-workflow-viewer';
const afterRunProps: any[] = [];
vi.mock('@/v2/AfterRunReport', () => ({AfterRunReport:(props:any)=>{afterRunProps.push(props);return null}}));
vi.mock('./feedback/report-confusion-button',()=>({ReportConfusionButton:()=>null}));
vi.mock('./feedback/download-outcome-prompt',()=>({DownloadOutcomePrompt:()=>null}));
beforeEach(()=>{vi.stubGlobal('fetch',vi.fn(async()=>({ok:false,status:404,json:async()=>({}),text:async()=>''})));});

describe('recorded recovery capability and directly accessible settings',()=>{
  it('one diagnosis: the card leads with the specific cause and the report omits its own (dev run c0d27792)',()=>{
    afterRunProps.length=0;
    const failure={category:'tool_error',user_message:'The step stopped with an error from the tool itself: cannot make 5 folds from 1 rows',suggested_action:'check_input',
      error_detail:'cannot make 5 folds from 1 rows',task_error_snippet:'  File "[path]", line 168, in kfold_split\nValueError: cannot make 5 folds from 1 rows'};
    render(<NextflowWorkflowViewer runId="failed-train" status="failed" workflowDefinition={{name:'contrasts-variable',steps:{s1:{name:'TRAIN'}}}} nextflowStatus={{failure}}/>);
    const cause=screen.getByTestId('failure-diagnosis-cause');
    expect(cause.getAttribute('data-failure-class')).toBe('too_few_rows');
    expect(cause).toHaveTextContent(/only 1 usable row/);
    expect(afterRunProps.at(-1)?.hideFailureDiagnosis).toBe(true);
  });
  it('renders the category sentence from the locale, quoting the tool\'s own message (dev run c0d27792)',()=>{
    const server='The step stopped with an error from the tool itself: cannot make 5 folds from 1 rows Check the input data and parameters against it, then run again.';
    expect(failureDiagnosisMessage(server,false,'tool_error','cannot make 5 folds from 1 rows'))
      .toBe('The step stopped with an error from the tool itself: cannot make 5 folds from 1 rows');
    expect(failureDiagnosisMessage('anything',false,'unknown')).toBe('The run stopped before completing.');
    // arch_compat keeps the server's own (bilingual) message.
    expect(failureDiagnosisMessage('此工作流… (Workflow container image has no ARM64 build.)',true,'arch_compat')).toContain('ARM64');
  });
  it('preserves the cause while removing a server resume promise with no recorded checkpoint',()=>{
    const message='The run stopped before completing. You can resume from the last completed step.';
    expect(failureDiagnosisMessage(message,false)).toBe('The run stopped before completing.');
    expect(failureDiagnosisMessage(message,true)).toBe(message);
    render(<NextflowWorkflowViewer runId="failed-owned" status="failed" workflowDefinition={{name:'Launch failure',steps:{s1:{name:'First step'}}}} nextflowStatus={{failure:{user_message:message,suggested_action:'resume'}}}/>);
    expect(screen.getByText('The run stopped before completing.')).toBeTruthy();
    expect(screen.queryByText(/You can resume/)).toBeNull();
    expect(screen.getByTestId('failure-recovery-advice')).toHaveTextContent('No completed step');
  });

  it('needs only the Optional parameters disclosure to reach editable settings',()=>{
    const onParameterChange=vi.fn();
    render(<NextflowWorkflowViewer status="idle" onParameterChange={onParameterChange} workflowDefinition={{name:'Editable settings',steps:{s1:{name:'First step'}},optional_params:[{name:'threshold',label:'Threshold',type:'number',default:4}]}}/>);
    expect(screen.queryByTestId('button-toggle-workflow-settings')).toBeNull();
    fireEvent.click(screen.getByText('Optional parameters'));
    fireEvent.change(screen.getByRole('spinbutton'),{target:{value:'8'}});
    expect(onParameterChange).toHaveBeenCalledWith('threshold',8);
  });
});
