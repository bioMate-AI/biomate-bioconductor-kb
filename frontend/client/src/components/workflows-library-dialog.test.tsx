/**
 * Workflows library — the unified surface that replaces the dead
 * StarredWorkflowsDialog. Coverage:
 *   1. Browse tab issues a real POST /api/ai_assistant/search_ranked and renders
 *      the ranked results the engine returns (name, domain, score) — numbers are
 *      rendered as returned, never invented.
 *   2. Clicking "Run" on a result seeds the chat (reusing the established seed
 *      path) and closes the dialog.
 *   3. "My workflows" tab renders the user's personal/uploaded workflows from
 *      GET /api/workflows/personal.
 *   4. The sidebar "Workflows" entry opens the library — NOT the dead
 *      StarredWorkflowsDialog.
 *
 * Only fetch is mocked (no msw, no live server).
 */
import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

vi.mock('@/lib/analytics', () => ({ analytics: { track: vi.fn() } }));

import { WorkflowsLibraryDialog } from './workflows-library-dialog';
import { stashWorkflowSelection, takeWorkflowSelection } from '@/lib/workflow-selection';

const RANKED = {
  query: 'rna-seq',
  results: [
    { rank: 1, name: 'nf-core/rnaseq', display_name: 'nf-core/rnaseq', description: 'Bulk RNA-seq quantification and QC.', domain: 'transcriptomics', source: 'nfcore', format: 'nextflow', score: 14.3, type: 'workflow', id: 42, nextflow_path: 'biomni_workflows/nfcore/rnaseq/main.nf' },
    { rank: 2, name: 'DESeq2', display_name: 'DESeq2 differential expression', description: 'Differential gene expression.', domain: 'transcriptomics', source: 'bioconductor', format: 'r', score: 9.1, type: 'workflow' },
  ],
};

const PERSONAL = [
  { id: 'wf-1', workflow_name: 'My custom pipeline', description: 'Imported NF', file_type: 'nf', created_at: '2026-11-01T00:00:00.000Z' },
];

let fetchMock: any;

beforeEach(() => {
  fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
    if (typeof url === 'string' && url.includes('/api/ai_assistant/search_ranked')) {
      return { ok: true, status: 200, json: async () => RANKED } as Response;
    }
    if (typeof url === 'string' && url.includes('/api/workflows/personal')) {
      return { ok: true, status: 200, json: async () => PERSONAL } as Response;
    }
    return { ok: true, status: 200, json: async () => ({}), text: async () => '' } as Response;
  });
  global.fetch = fetchMock;
});
afterEach(() => { vi.clearAllMocks(); });

describe('WorkflowsLibraryDialog — Browse (ranked search)', () => {
  it('calls /api/ai_assistant/search_ranked and renders the ranked results', async () => {
    render(<WorkflowsLibraryDialog open onOpenChange={() => {}} onSeedChat={() => {}} />);

    // Opens on the Browse tab; no search fired yet.
    const input = await screen.findByTestId('browse-search-input');
    fireEvent.change(input, { target: { value: 'rna-seq' } });

    await waitFor(() => {
      expect(fetchMock.mock.calls.some((c: any[]) =>
        typeof c[0] === 'string' && c[0].includes('/api/ai_assistant/search_ranked')
      )).toBe(true);
    });

    // Results render with the engine's name and domain (not invented). The raw ranking score and
    // the internal catalog source tag are NOT shown (founder 2026-11-12: "评分 52.1" /
    // "biomni_nextflow" mean nothing to a user).
    expect(await screen.findByText('nf-core/rnaseq')).toBeInTheDocument();
    expect(screen.getByText('DESeq2 differential expression')).toBeInTheDocument();
    expect(screen.getAllByTestId('browse-result-domain').map((e) => e.textContent)).toContain('transcriptomics');
    expect(screen.queryByText(/14\.3/)).toBeNull();
    expect(screen.queryByText('nfcore')).toBeNull();
    expect(screen.queryByText('bioconductor')).toBeNull();

    // The request body carried the typed query.
    const call = fetchMock.mock.calls.find((c: any[]) => typeof c[0] === 'string' && c[0].includes('search_ranked'));
    expect(JSON.parse(call[1].body).query).toBe('rna-seq');
  });

  it('clicking Run seeds the chat and closes the dialog', async () => {
    const onSeedChat = vi.fn();
    const onOpenChange = vi.fn();
    render(<WorkflowsLibraryDialog open onOpenChange={onOpenChange} onSeedChat={onSeedChat} />);

    fireEvent.change(await screen.findByTestId('browse-search-input'), { target: { value: 'rna-seq' } });
    const runBtn = await screen.findByTestId('button-run-catalog-1');
    fireEvent.click(runBtn);

    expect(onSeedChat).toHaveBeenCalledTimes(1);
    expect(onSeedChat.mock.calls[0][0]).toContain('nf-core/rnaseq');
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  // §7.2: the pick carries the workflow's catalog identity (structured), and the visible
  // sentence carries no ids or paths.
  it('Run passes the selected workflow identity alongside a plain sentence', async () => {
    const onSeedChat = vi.fn();
    render(<WorkflowsLibraryDialog open onOpenChange={() => {}} onSeedChat={onSeedChat} />);

    fireEvent.change(await screen.findByTestId('browse-search-input'), { target: { value: 'rna-seq' } });
    fireEvent.click(await screen.findByTestId('button-run-catalog-1'));

    const [prompt, selection] = onSeedChat.mock.calls[0];
    expect(selection).toEqual({
      name: 'nf-core/rnaseq', id: 42, nextflow_path: 'biomni_workflows/nfcore/rnaseq/main.nf', source: 'nfcore', type: 'workflow',
    });
    expect(prompt).not.toMatch(/main\.nf|biomni_workflows|\b42\b/);
  });

  it('default seed path parks the selection for the next send of that draft', async () => {
    const assign = vi.fn();
    const orig = window.location;
    Object.defineProperty(window, 'location', { configurable: true, value: { ...orig, assign } });
    try {
      render(<WorkflowsLibraryDialog open onOpenChange={() => {}} />);
      fireEvent.change(await screen.findByTestId('browse-search-input'), { target: { value: 'rna-seq' } });
      fireEvent.click(await screen.findByTestId('button-run-catalog-1'));
      expect(assign.mock.calls[0][0]).toMatch(/^\/\?draft=/);
      const draft = new URLSearchParams(String(assign.mock.calls[0][0]).slice(1)).get('draft')!;
      expect(takeWorkflowSelection(draft)).toMatchObject({ name: 'nf-core/rnaseq', id: 42 });
      expect(takeWorkflowSelection(draft)).toBeUndefined(); // one-shot
    } finally {
      Object.defineProperty(window, 'location', { configurable: true, value: orig });
    }
  });
});

describe('takeWorkflowSelection', () => {
  it('applies only while the sent message still names the picked workflow', () => {
    stashWorkflowSelection({ name: 'nf-core/rnaseq' });
    expect(takeWorkflowSelection('Run the nf-core/rnaseq workflow on SRR1039508')).toEqual({ name: 'nf-core/rnaseq' });
    stashWorkflowSelection({ name: 'nf-core/rnaseq' });
    expect(takeWorkflowSelection('actually, dock these ligands instead')).toBeUndefined();
    stashWorkflowSelection({ name: 'deseq2_de', label: 'DESeq2 differential expression' });
    expect(takeWorkflowSelection('运行 DESeq2 differential expression 工作流。')).toMatchObject({ name: 'deseq2_de' });
  });
});

describe('WorkflowsLibraryDialog — My workflows', () => {
  it('renders the user personal/uploaded workflows from /api/workflows/personal', async () => {
    render(<WorkflowsLibraryDialog open onOpenChange={() => {}} onSeedChat={() => {}} />);

    fireEvent.click(await screen.findByTestId('tab-my-imports'));

    await waitFor(() => {
      expect(fetchMock.mock.calls.some((c: any[]) =>
        typeof c[0] === 'string' && c[0].includes('/api/workflows/personal')
      )).toBe(true);
    });
    expect(await screen.findByText('My custom pipeline')).toBeInTheDocument();
    expect(screen.getByTestId('personal-workflow-row-wf-1')).toBeInTheDocument();
  });
});
