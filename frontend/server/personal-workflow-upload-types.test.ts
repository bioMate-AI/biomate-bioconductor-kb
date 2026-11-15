/**
 * Defense-in-depth: POST /api/workflows/upload-file multer filter rejects .ga
 * while GA_IMPORT_ENABLED is false. Re-enable is one flip in shared module.
 */
import { readFileSync } from 'fs';
import { join } from 'path';
import { describe, expect, it } from 'vitest';
import {
  ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS,
  GA_IMPORT_ENABLED,
  PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE,
  isAllowedPersonalWorkflowName,
} from '@shared/personal-workflow-import';

describe('personal workflow upload API allowlist', () => {
  it('GA_IMPORT_ENABLED gates .ga off for now', () => {
    expect(GA_IMPORT_ENABLED).toBe(false);
    expect(ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS).not.toContain('.ga');
    expect(isAllowedPersonalWorkflowName('x.ga')).toBe(false);
    expect(isAllowedPersonalWorkflowName('main.nf')).toBe(true);
  });

  it('routes.ts wires shared allowlist (easy to revert with GA_IMPORT_ENABLED)', () => {
    const src = readFileSync(join(__dirname, 'routes.ts'), 'utf8');
    expect(src).toContain('isAllowedPersonalWorkflowName');
    expect(src).toContain('PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE');
    expect(src).not.toMatch(/\['\.nf',\s*'\.ga',\s*'\.yml',\s*'\.yaml'\]/);
    expect(src).not.toMatch(/Only \.nf, \.ga, \.yml/);
  });

  it('rejection copy is clear for API clients', () => {
    expect(PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE).toMatch(/cannot be imported/i);
  });
});
