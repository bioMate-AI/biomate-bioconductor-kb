/**
 * W10 (dataset panel round 3): "Run full QC" does what it says — the chat opens in the project
 * with the dataset attached and the QC request SENT (not left as an unsent draft). The composer
 * sends it only once the attached project file is linked, so the request always carries the exact
 * file reference (no attach/send race). A plain draft (no `send`) still waits for the user.
 */
import React from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor, act } from '@testing-library/react';
import { ChatInput } from './chat-input';
import { runQcChatUrl } from '@/pages/data-hub';

vi.mock('./skills-selector', () => ({ SkillsSelector: () => null }));

function stubFetch() {
  let release: () => void = () => {};
  const gate = new Promise<void>((r) => { release = r; });
  vi.stubGlobal('fetch', vi.fn(async (url: string) => {
    if (url.endsWith('/url')) { await gate; return { ok: true, json: async () => ({ name: 'counts.tsv' }) }; }
    return { ok: true, json: async () => ({ settings: { outputRequirements: '', skillPackIds: [] } }) };
  }));
  return () => release();
}

describe('Run full QC — the request is sent, after the file is linked', () => {
  afterEach(() => { vi.unstubAllGlobals(); window.history.replaceState(null, '', '/'); });

  it('the data panel builds a chat link that asks for sending (send=1) with the file attached', () => {
    const url = new URL(runQcChatUrl('project-a', 'file-a'), 'http://x');
    expect(url.searchParams.get('project')).toBe('project-a');
    expect(url.searchParams.getAll('attachFile')).toEqual(['file-a']);
    expect(url.searchParams.get('draft')).toBeTruthy();
    expect(url.searchParams.get('send')).toBe('1');
  });

  it('a draft applied with {send: true} is sent once the attached file is linked — with its reference', async () => {
    window.history.replaceState(null, '', '/?project=project-a&attachFile=file-a');
    const release = stubFetch();
    const onSend = vi.fn();
    let setDraft: ((d: string, o?: { send?: boolean }) => void) | undefined;
    render(<ChatInput activeProjectId="project-a" onSend={onSend} onRegisterSetDraft={(s) => { setDraft = s; }} />);
    await waitFor(() => expect(setDraft).toBeDefined());
    act(() => setDraft!('Run a full quality check on this dataset.', { send: true }));
    // Not before the file is linked: the request must carry the exact file.
    await new Promise((r) => setTimeout(r, 30));
    expect(onSend).not.toHaveBeenCalled();
    release();
    await waitFor(() => expect(onSend).toHaveBeenCalledTimes(1));
    expect(onSend.mock.calls[0][0]).toContain('Run a full quality check on this dataset.');
    expect(onSend.mock.calls[0][2].datasetReferences).toEqual([{ id: 'file-a', name: 'counts.tsv' }]);
    expect(screen.getByTestId('chat-input')).toHaveValue('');
  });

  it('a plain draft (no send) stays in the composer for review', async () => {
    window.history.replaceState(null, '', '/?project=project-a&attachFile=file-a');
    const release = stubFetch();
    release();
    const onSend = vi.fn();
    let setDraft: ((d: string, o?: { send?: boolean }) => void) | undefined;
    render(<ChatInput activeProjectId="project-a" onSend={onSend} onRegisterSetDraft={(s) => { setDraft = s; }} />);
    await waitFor(() => expect(setDraft).toBeDefined());
    act(() => setDraft!('Review me first.'));
    expect(await screen.findByTestId('composer-dataset-ref')).toHaveTextContent('counts.tsv');
    await new Promise((r) => setTimeout(r, 30));
    expect(onSend).not.toHaveBeenCalled();
    expect(screen.getByTestId('chat-input')).toHaveValue('Review me first.');
  });
});
