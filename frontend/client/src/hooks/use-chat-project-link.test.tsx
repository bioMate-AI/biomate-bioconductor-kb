import React, { useState } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { useChatProjectLink } from './use-chat-project-link';

function Harness({ search, authenticated = true, initial = 'previous-project' }: {
  search: string; authenticated?: boolean; initial?: string;
}) {
  const [project, setProject] = useState<string | null>(initial);
  useChatProjectLink(search, authenticated, setProject);
  return <output data-testid="selected-project">{project || 'unfiled'}</output>;
}

describe('dataset-to-chat project context', () => {
  it('activates the linked project in a fresh unfiled browser', async () => {
    render(<Harness initial="" search="?project=target-project&attachFile=file-a" />);
    await waitFor(() => expect(screen.getByTestId('selected-project')).toHaveTextContent('target-project'));
  });
  it('activates the linked project for a folder attach', async () => {
    render(<Harness initial="" search="?project=target-project&attachFolder=pairs" />);
    await waitFor(() => expect(screen.getByTestId('selected-project')).toHaveTextContent('target-project'));
  });
  it('replaces a previously selected project, retaining both file parameters', async () => {
    const search = '?project=target-project&attachFile=file-a&attachFile=file-b&draft=Compare%20files';
    const replace = vi.spyOn(window.history, 'replaceState');
    render(<Harness search={search} />);
    await waitFor(() => expect(screen.getByTestId('selected-project')).toHaveTextContent('target-project'));
    expect(replace).not.toHaveBeenCalled();
    replace.mockRestore();
  });
  it('waits for authentication before changing context', async () => {
    const view = render(<Harness authenticated={false} search="?project=target-project&attachFile=file-a" />);
    expect(screen.getByTestId('selected-project')).toHaveTextContent('previous-project');
    view.rerender(<Harness authenticated search="?project=target-project&attachFile=file-a" />);
    await waitFor(() => expect(screen.getByTestId('selected-project')).toHaveTextContent('target-project'));
  });
  it.each(['', '?q=Explain%20RNA', '?project=target-project', '?project=&attachFile=file-a',
    '?project=target-project&attachFile=%20%20', '?attachFile=file-a'])('leaves ordinary context alone: %s', search => {
    render(<Harness search={search} />);
    expect(screen.getByTestId('selected-project')).toHaveTextContent('previous-project');
  });
});
