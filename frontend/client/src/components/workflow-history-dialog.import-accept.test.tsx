/**
 * Import Workflow tab — fail-closed Nextflow-only accept list (no Galaxy .ga).
 */
import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import {
  PERSONAL_WORKFLOW_ACCEPT_ATTR,
  PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE,
} from '@shared/personal-workflow-import';

vi.mock('@/lib/analytics', () => ({ analytics: { track: vi.fn() } }));
vi.mock('@/lib/i18n', () => ({
  t: (k: string) => k,
  tOr: (_k: string, fallback: string) => fallback,
}));
vi.mock('@/lib/use-localized-labels', () => ({
  useLocalizedLabels: () => ({ t: (k: string) => k }),
}));

import { WorkflowHistoryDialog } from './workflow-history-dialog';

beforeEach(() => {
  global.fetch = vi.fn(async () => ({
    ok: true,
    status: 200,
    json: async () => [],
  })) as any;
});
afterEach(() => {
  vi.clearAllMocks();
});

describe('WorkflowHistoryDialog — import accept list', () => {
  it('file input accept omits .ga and lists Nextflow extensions', async () => {
    render(
      <WorkflowHistoryDialog open onOpenChange={() => {}} importOnly initialTab="upload" />
    );
    const input = await screen.findByTestId('workflow-file-input');
    expect(input.getAttribute('accept')).toBe(PERSONAL_WORKFLOW_ACCEPT_ATTR);
    expect(input.getAttribute('accept')).not.toContain('.ga');
    expect(screen.getByTestId('workflow-upload-modal').textContent).toMatch(/\.nf/);
    expect(screen.getByTestId('workflow-upload-modal').textContent).not.toMatch(/\.ga\s*\/|\.ga,/);
  });

  it('client-side rejects a .ga selection with clear error', async () => {
    render(
      <WorkflowHistoryDialog open onOpenChange={() => {}} importOnly initialTab="upload" />
    );
    const input = await screen.findByTestId('workflow-file-input');
    const file = new File(['{"a_galaxy_workflow":"true"}'], 'legacy.ga', {
      type: 'application/json',
    });
    fireEvent.change(input, { target: { files: [file] } });
    expect(screen.getByText(PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE)).toBeInTheDocument();
    expect(screen.getByTestId('workflow-upload-submit')).toBeDisabled();
  });
});
