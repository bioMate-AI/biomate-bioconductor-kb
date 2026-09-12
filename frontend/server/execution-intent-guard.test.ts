import { describe, expect, it } from 'vitest';
import { isInterpretationOnlyRequest, prohibitsWorkflowExecution } from './execution-intent-guard';

describe('execution-intent guard', () => {
  const blockedInterpretationRequests = [
    'Interpret these PK results only: Cmax 2.4 ng/mL, AUC 18.1 ng·h/mL, t1/2 6.2 h. Do not launch PBPK.',
    'Please explain whether CLint 14 µL/min/mg and fu 0.08 are plausible; do not run a workflow.',
    'No simulation or compute: assess the exposure numbers I pasted and tell me what they mean.',
    "Don't execute anything. Review this PK table and flag the clinical implications.",
    'Without running Nextflow, summarize the PBPK output and its limitations.',
    'For interpretation only — do not submit a job — compare the observed and predicted AUC values.',
  ];

  it.each(blockedInterpretationRequests)('blocks workflow execution for: %s', (message) => {
    expect(prohibitsWorkflowExecution(message)).toBe(true);
    expect(isInterpretationOnlyRequest(message)).toBe(true);
  });

  it.each([
    'Run PBPK with SMILES CC(=O)Oc1ccccc1C(=O)O, CLint 14 µL/min/mg, and fu 0.08.',
    'Do not just explain PBPK; run the simulation with these parameters.',
    'Explain how to run a PBPK workflow for an oral compound.',
    'Before we run PBPK tomorrow, what additional clearance measurements should we collect?',
  ])('does not mistake a planning or execution request for a prohibition: %s', (message) => {
    expect(prohibitsWorkflowExecution(message)).toBe(false);
  });
});
