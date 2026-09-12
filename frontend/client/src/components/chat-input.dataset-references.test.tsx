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
});
