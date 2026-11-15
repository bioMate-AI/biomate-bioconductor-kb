/**
 * Defense-in-depth: POST /api/workflows/upload-file multer filter must reject .ga.
 * Asserts against the shared allowlist + the routes.ts wiring (source scan).
 */
import { readFileSync } from 'fs';
import { join } from 'path';
import { describe, expect, it } from 'vitest';
import {
  ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS,
  PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE,
  isAllowedPersonalWorkflowName,
} from '@shared/personal-workflow-import';

describe('personal workflow upload API allowlist', () => {
  it('shared allowlist has no .ga', () => {
    expect(ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS).not.toContain('.ga');
    expect(isAllowedPersonalWorkflowName('x.ga')).toBe(false);
    expect(isAllowedPersonalWorkflowName('main.nf')).toBe(true);
  });

  it('routes.ts wires shared reject for .ga (not the old .ga allowlist)', () => {
    const src = readFileSync(join(__dirname, 'routes.ts'), 'utf8');
    expect(src).toContain('isAllowedPersonalWorkflowName');
    expect(src).toContain('PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE');
    // Old inline allowlist must not return.
    expect(src).not.toMatch(/\['\.nf',\s*'\.ga',\s*'\.yml',\s*'\.yaml'\]/);
    expect(src).not.toMatch(/Only \.nf, \.ga, \.yml/);
  });

  it('rejection copy is clear for API clients', () => {
    expect(PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE).toMatch(/cannot be imported/i);
  });
});
