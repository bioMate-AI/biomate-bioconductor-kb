import { describe, expect, it } from 'vitest';
import {
  ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS,
  PERSONAL_WORKFLOW_ACCEPT_ATTR,
  PERSONAL_WORKFLOW_ACCEPT_LABEL,
  PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE,
  isAllowedPersonalWorkflowName,
  personalWorkflowExt,
} from './personal-workflow-import';

describe('personal-workflow-import', () => {
  it('allows Nextflow .nf / .yml / .yaml only', () => {
    expect(ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS).toEqual(['.nf', '.yml', '.yaml']);
    expect(isAllowedPersonalWorkflowName('pipe.nf')).toBe(true);
    expect(isAllowedPersonalWorkflowName('params.YML')).toBe(true);
    expect(isAllowedPersonalWorkflowName('config.yaml')).toBe(true);
  });

  it('rejects Galaxy .ga (and other non-Nextflow extensions)', () => {
    expect(isAllowedPersonalWorkflowName('legacy.ga')).toBe(false);
    expect(isAllowedPersonalWorkflowName('workflow.GA')).toBe(false);
    expect(isAllowedPersonalWorkflowName('notes.txt')).toBe(false);
    expect(isAllowedPersonalWorkflowName('noext')).toBe(false);
  });

  it('accept attr / label omit .ga', () => {
    expect(PERSONAL_WORKFLOW_ACCEPT_ATTR).toBe('.nf,.yml,.yaml');
    expect(PERSONAL_WORKFLOW_ACCEPT_LABEL).toBe('.nf, .yml, .yaml');
    expect(PERSONAL_WORKFLOW_ACCEPT_ATTR).not.toContain('.ga');
    expect(PERSONAL_WORKFLOW_ACCEPT_LABEL).not.toContain('.ga');
  });

  it('unsupported message names .ga and lists Nextflow formats', () => {
    expect(PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE).toMatch(/\.ga/i);
    expect(PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE).toMatch(/Nextflow/i);
    expect(PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE).toContain('.nf');
  });

  it('personalWorkflowExt returns lowercase extension including dot', () => {
    expect(personalWorkflowExt('a/b/Main.NF')).toBe('.nf');
    expect(personalWorkflowExt('x.ga')).toBe('.ga');
  });
});
