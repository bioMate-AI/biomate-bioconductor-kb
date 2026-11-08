/**
 * RTL tests for <FindingsCard> §7.8 — findings numbers → output links.
 * We test the pure linkifier (the load-bearing new logic); the surrounding
 * card fetches from the live API on mount and is covered elsewhere.
 */
import { describe, it, expect, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { FindingsCard, linkifyFindings } from './findings-card'

const KR = [
  { metric: 'DEGs', value: '1284', interpretation: 'up', source_file: 'results/degs.csv' },
  { metric: 'padj', value: '0.05', interpretation: 'threshold', source_file: 'results/summary.tsv' },
]

describe('linkifyFindings', () => {
  it('links a number that matches a KeyResult value to its source_file', async () => {
    const onOpenOutput = vi.fn()
    render(<p>{linkifyFindings('We found 1284 DEGs at padj 0.05.', KR, onOpenOutput)}</p>)
    const links = screen.getAllByTestId('finding-number-link')
    expect(links).toHaveLength(2)
    expect(links[0]).toHaveAttribute('data-output-ref', 'results/degs.csv')
    expect(links[1]).toHaveAttribute('data-output-ref', 'results/summary.tsv')

    const user = userEvent.setup()
    await user.click(links[0])
    expect(onOpenOutput).toHaveBeenCalledWith('results/degs.csv')
  })

  it('leaves numbers with no resolvable output as plain text (no fabricated link)', () => {
    const onOpenOutput = vi.fn()
    render(<p>{linkifyFindings('Ran for 42 minutes on 8 cores.', KR, onOpenOutput)}</p>)
    expect(screen.queryByTestId('finding-number-link')).toBeNull()
    expect(screen.getByText(/Ran for 42 minutes on 8 cores\./)).toBeInTheDocument()
  })

  it('does not link when no callback is provided', () => {
    render(<p>{linkifyFindings('We found 1284 DEGs.', KR, undefined)}</p>)
    expect(screen.queryByTestId('finding-number-link')).toBeNull()
    expect(screen.getByText(/1284/)).toBeInTheDocument()
  })

  it('handles empty text safely', () => {
    expect(linkifyFindings('', KR, vi.fn())).toEqual([''])
  })
})

describe('FindingsCard output-readability state', () => {
  it('does not render a ready-looking findings card when outputs are unreadable', async () => {
    const fetchMock = vi.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => ({
        status: 'unavailable',
        message: 'Workflow output files could not be read.',
      }),
    } as Response)

    render(<FindingsCard runId="run-output-access-failed" executionStatus="completed" />)

    await waitFor(() => {
      expect(screen.getByTestId('findings-unavailable')).toHaveTextContent(
        'Workflow output files could not be read.',
      )
    })
    expect(screen.queryByTestId('findings-card')).toBeNull()
    fetchMock.mockRestore()
  })

  it('shows a paused (not failed, not in-progress) message for a QC-gate-paused run', async () => {
    // Regression: a paused run (QC-gate halt) must not render the failed
    // "did not complete successfully" message, nor the "Analysis in progress…"
    // spinner (it is halted, not working). It should show the paused message.
    const fetchMock = vi.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => ({ status: 'pending' }),
    } as Response)

    render(<FindingsCard runId="run-paused-qc-gate" executionStatus="paused" />)

    await waitFor(() => {
      expect(screen.getByText(/Paused at a QC gate/i)).toBeInTheDocument()
    })
    expect(screen.queryByText(/did not complete successfully/i)).toBeNull()
    expect(screen.queryByText(/Analysis in progress/i)).toBeNull()
    fetchMock.mockRestore()
  })
})

it('distinguishes a completed workflow from an unavailable findings', async () => {
 const fetcher = vi.spyOn(global, 'fetch').mockResolvedValue({ ok: true, json: async () => ({ status: 'pending' }) } as Response);
 render(<FindingsCard runId="completed-run" executionStatus="completed" />);
 expect(await screen.findByText('Findings are not available yet.')).toBeInTheDocument();
 expect(screen.queryByText('Analysis in progress…')).toBeNull();
 fetcher.mockRestore();
});
