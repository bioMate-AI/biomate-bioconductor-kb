import { describe, expect, it } from 'vitest';
import {
  ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS,
  GA_IMPORT_ENABLED,
  PERSONAL_WORKFLOW_ACCEPT_ATTR,
  PERSONAL_WORKFLOW_ACCEPT_LABEL,
  PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE,
  isAllowedPersonalWorkflowName,
  personalWorkflowExt,
} from './personal-workflow-import';

describe('personal-workflow-import', () => {
  it('GA_IMPORT_ENABLED is the single flip (currently off)', () => {
    // Temporary fail-closed — flip to true when .ga execution is supported.
    expect(GA_IMPORT_ENABLED).toBe(false);
  });

  it('allows Nextflow .nf / .yml / .yaml', () => {
    expect(isAllowedPersonalWorkflowName('pipe.nf')).toBe(true);
    expect(isAllowedPersonalWorkflowName('params.YML')).toBe(true);
    expect(isAllowedPersonalWorkflowName('config.yaml')).toBe(true);
  });

  it('rejects Galaxy .ga while GA_IMPORT_ENABLED is false', () => {
    expect(ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS).not.toContain('.ga');
    expect(isAllowedPersonalWorkflowName('legacy.ga')).toBe(false);
    expect(isAllowedPersonalWorkflowName('workflow.GA')).toBe(false);
    expect(isAllowedPersonalWorkflowName('notes.txt')).toBe(false);
  });

  it('accept attr / label omit .ga while gated off', () => {
    expect(PERSONAL_WORKFLOW_ACCEPT_ATTR).toBe('.nf,.yml,.yaml');
    expect(PERSONAL_WORKFLOW_ACCEPT_LABEL).toBe('.nf, .yml, .yaml');
    expect(PERSONAL_WORKFLOW_ACCEPT_ATTR).not.toContain('.ga');
  });

  it('unsupported message names .ga and lists Nextflow formats', () => {
    expect(PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE).toMatch(/\.ga/i);
    expect(PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE).toMatch(/Nextflow|temporary/i);
    expect(PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE).toContain('.nf');
  });

  it('personalWorkflowExt returns lowercase extension including dot', () => {
    expect(personalWorkflowExt('a/b/Main.NF')).toBe('.nf');
    expect(personalWorkflowExt('x.ga')).toBe('.ga');
  });
});
