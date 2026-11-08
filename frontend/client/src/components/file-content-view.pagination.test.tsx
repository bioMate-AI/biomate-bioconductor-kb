import React from 'react';
import { render, screen, fireEvent, within } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import { InlineTableViewer } from './file-content-view';
vi.mock('@/lib/i18n', () => ({t: (key: string) => key, tOr: (_: string, fallback: string) => fallback}));
describe('complete output table navigation', () => {
  it.each(['tsv', 'json', 'star'])('makes rows beyond the inline limit accessible in %s files', ext => {
    const data = Array.from({length: 405}, (_, i) => ({id: `record-${i + 1}`}));
    const text = ext === 'json' ? JSON.stringify(data) : ext === 'star' ? `data_test\nloop_\n_rlnName #1\n${data.map(r => r.id).join('\n')}` : `id\n${data.map(r => r.id).join('\n')}`;
    render(<InlineTableViewer text={text} ext={ext} complete />);
    expect(within(screen.getByRole('table')).getByText('record-1')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', {name: 'Next rows'}));
    expect(screen.getByText('record-201')).toBeInTheDocument();
    expect(screen.queryByText('record-1')).toBeNull();
    fireEvent.click(screen.getByRole('button', {name: 'Next rows'}));
    expect(screen.getByText('record-405')).toBeInTheDocument();
    expect(screen.getByRole('button', {name: 'Next rows'})).toBeDisabled();
    fireEvent.click(screen.getByRole('button', {name: 'Previous rows'}));
    expect(screen.getByText('record-201')).toBeInTheDocument();
  });
});
