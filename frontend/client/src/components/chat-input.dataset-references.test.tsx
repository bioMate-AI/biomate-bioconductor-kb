import React from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { ChatInput } from './chat-input';

vi.mock('./galaxy-dataset-browser', () => ({
  GalaxyDatasetBrowser: ({ onSelect }: { onSelect: (id: string, name: string) => void }) => (
    <button type="button" data-testid="select-two-project-files" onClick={() => {
      onSelect('result-a-v1', 'result-A.csv');
      onSelect('result-b-v2', 'result-B.csv');
    }}>
      Select project files
    </button>
  ),
}));

// This suite verifies the composer-to-request reference contract.  The live
// skills catalogue fetch is unrelated and its asynchronous state update makes
// a synchronous composer assertion emit React act() warnings, obscuring real
// test failures.  Keep it inert here; SkillsSelector has its own coverage.
vi.mock('./skills-selector', () => ({
  SkillsSelector: () => null,
}));

describe('ChatInput — request-scoped dataset references', () => {
  afterEach(() => { vi.unstubAllGlobals(); window.history.replaceState(null, '', '/'); });
  it('links a project file by ID with an empty query and waits for user intent', async () => {
    window.history.replaceState(null, '', '/?project=project-a&attachFile=file-a');
    const fetch = vi.fn(async (url: string) => ({ ok: true, json: async () => url.endsWith('/url')
      ? { name: 'QUICKSTART.txt', url: 'https://files.example/real-file' }
      : { settings: { outputRequirements: '', skillPackIds: [] } } }));
    vi.stubGlobal('fetch', fetch);
    const onSend = vi.fn();
    render(<ChatInput activeProjectId="project-a" onSend={onSend} />);
    expect(await screen.findByTestId('composer-dataset-ref')).toHaveTextContent('QUICKSTART.txt');
    expect(screen.getByTestId('chat-input')).toHaveValue('');
    expect(screen.getByTestId('chat-send-button')).toBeDisabled();
    expect(onSend).not.toHaveBeenCalled();
    fireEvent.input(screen.getByTestId('chat-input'), { target: { value: 'Summarize this file.' } });
    await waitFor(() => expect(screen.getByTestId('chat-send-button')).not.toBeDisabled());
    fireEvent.click(screen.getByTestId('chat-send-button'));
    expect(onSend.mock.calls[0][2].datasetReferences).toEqual([{ id: 'file-a', name: 'QUICKSTART.txt' }]);
    expect(onSend.mock.calls[0][0]).not.toContain('suggest the right workflow');
  });

  it('links both project datasets from a model round setup URL without sending', async () => {
    window.history.replaceState(null, '', '/?project=project-a&attachFile=assays&attachFile=candidates');
    vi.stubGlobal('fetch', vi.fn(async (url: string) => ({ ok: true, json: async () => url.endsWith('/url')
      ? { name: url.includes('/assays/') ? 'measured.csv' : 'candidates.csv' }
      : { settings: { outputRequirements: '', skillPackIds: [] } } })));
    const onSend = vi.fn(); render(<ChatInput activeProjectId="project-a" onSend={onSend} />);
    await waitFor(() => expect(screen.getAllByTestId('composer-dataset-ref')).toHaveLength(2));
    expect(screen.getByTestId('chat-input')).toHaveValue(''); expect(onSend).not.toHaveBeenCalled();
    expect(window.location.search).not.toContain('attachFile');
    fireEvent.input(screen.getByTestId('chat-input'), { target: { value: 'Prepare my next round for confirmation.' } });
    fireEvent.click(screen.getByTestId('chat-send-button'));
    expect(onSend.mock.calls[0][2].datasetReferences.map((item: { id: string }) => item.id)).toEqual(['assays', 'candidates']);
  });

  it('expands attachFolder to every file under the folder as the analysis input set', async () => {
    window.history.replaceState(null, '', '/?project=project-a&attachFolder=pairs');
    vi.stubGlobal('fetch', vi.fn(async (url: string) => {
      if (url.includes('/folders/files')) {
        return {
          ok: true,
          json: async () => ({
            path: 'pairs',
            files: [
              { id: 'f1', name: 'pairs/S1_R1.fastq.gz' },
              { id: 'f2', name: 'pairs/S1_R2.fastq.gz' },
              { id: 'f3', name: 'pairs/S2_R1.fastq.gz' },
            ],
          }),
        };
      }
      return { ok: true, json: async () => ({ settings: { outputRequirements: '', skillPackIds: [] } }) };
    }));
    const onSend = vi.fn();
    render(<ChatInput activeProjectId="project-a" onSend={onSend} />);
    await waitFor(() => expect(screen.getAllByTestId('composer-dataset-ref')).toHaveLength(3));
    expect(window.location.search).not.toContain('attachFolder');
    fireEvent.input(screen.getByTestId('chat-input'), { target: { value: 'Run QC on this folder.' } });
    fireEvent.click(screen.getByTestId('chat-send-button'));
    expect(onSend.mock.calls[0][2].datasetReferences.map((item: { id: string }) => item.id)).toEqual(['f1', 'f2', 'f3']);
  });

  it('expands attachFolder from ?project= even when activeProjectId has not caught up yet', async () => {
    // Live race: useChatProjectLink / chat-interface sync lag behind the URL.
    // Composer must still expand using the deep-link project id (not wait forever).
    window.history.replaceState(null, '', '/?project=project-a&attachFolder=pairs');
    const fetch = vi.fn(async (url: string) => {
      if (url.includes('/folders/files')) {
        expect(url).toContain('/projects/project-a/folders/files');
        return {
          ok: true,
          json: async () => ({
            path: 'pairs',
            files: [
              { id: 'f1', name: 'pairs/S1_R1.fastq.gz' },
              { id: 'f2', name: 'pairs/S1_R2.fastq.gz' },
            ],
          }),
        };
      }
      return { ok: true, json: async () => ({ settings: { outputRequirements: '', skillPackIds: [] } }) };
    });
    vi.stubGlobal('fetch', fetch);
    render(<ChatInput activeProjectId={null} onSend={vi.fn()} />);
    await waitFor(() => expect(screen.getAllByTestId('composer-dataset-ref')).toHaveLength(2));
    expect(window.location.search).not.toContain('attachFolder');
    expect(fetch.mock.calls.some(([u]) => String(u).includes('/folders/files'))).toBe(true);
  });

  it('waits to expand attachFolder when activeProjectId is a different project than ?project=', async () => {
    window.history.replaceState(null, '', '/?project=project-a&attachFolder=pairs');
    const fetch = vi.fn(async (_url: string) => ({ ok: true, json: async () => ({ files: [], settings: {} }) }));
    vi.stubGlobal('fetch', fetch);
    render(<ChatInput activeProjectId="project-other" onSend={vi.fn()} />);
    await new Promise((r) => setTimeout(r, 50));
    expect(screen.queryAllByTestId('composer-dataset-ref')).toHaveLength(0);
    expect(window.location.search).toContain('attachFolder=pairs');
    expect(fetch.mock.calls.some(([u]) => String(u).includes('/folders/files'))).toBe(false);
  });

  it('carries the exact selected project-file IDs with a multi-file comparison request', () => {
    const onSend = vi.fn();
    render(<ChatInput onSend={onSend} isStreaming={false} />);

    fireEvent.click(screen.getByTestId('select-two-project-files'));
    fireEvent.input(screen.getByTestId('chat-input'), {
      target: { value: 'Compare these two result files.' },
    });
    fireEvent.click(screen.getByTestId('chat-send-button'));

    expect(onSend).toHaveBeenCalledTimes(1);
    expect(onSend.mock.calls[0][0]).toContain('[BioMate dataset: result-A.csv (id: result-a-v1)]');
    expect(onSend.mock.calls[0][0]).toContain('[BioMate dataset: result-B.csv (id: result-b-v2)]');
    expect(onSend.mock.calls[0][2]).toMatchObject({
      datasetReferences: [
        { id: 'result-a-v1', name: 'result-A.csv' },
        { id: 'result-b-v2', name: 'result-B.csv' },
      ],
    });
  });

  it('renders each dataset chip as a live reference that deep-links to the object', () => {
    // Start from a clean URL so the post-click assertion proves THIS click
    // navigated — not stale location state left by another test.
    window.history.replaceState(null, '', '/');
    expect(window.location.search).not.toContain('file=');

    render(<ChatInput onSend={vi.fn()} isStreaming={false} />);
    fireEvent.click(screen.getByTestId('select-two-project-files'));

    const refs = screen.getAllByTestId('composer-dataset-ref');
    expect(refs).toHaveLength(2);
    // The chip is a button (clickable handle), not inert text, and carries the
    // object id so it resolves to the same DatasetObject in the data hub.
    expect(refs[0].tagName).toBe('BUTTON');
    expect(refs[0]).toHaveTextContent('result-A.csv');
    expect(refs[0].getAttribute('title')).toContain('result-a-v1');

    // Guard: not already at the target before the click.
    expect(window.location.search).not.toContain('file=result-a-v1');
    // Clicking navigates to the object deep-link (/files?file=<id>).
    fireEvent.click(refs[0]);
    expect(window.location.pathname).toBe('/files');
    expect(window.location.search).toContain('file=result-a-v1');

    // Distinct chip → distinct target (kills a hard-coded / first-match pass).
    fireEvent.click(refs[1]);
    expect(window.location.search).toContain('file=result-b-v2');
    expect(window.location.search).not.toContain('file=result-a-v1');
  });
});
