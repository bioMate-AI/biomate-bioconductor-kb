import React from 'react';
import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
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

describe('ChatInput — request-scoped dataset references', () => {
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
