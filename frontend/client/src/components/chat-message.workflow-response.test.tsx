import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
vi.mock('3dmol', () => ({ default: {}, GLViewer: class {}, createViewer: () => ({}) }))
import { ChatMessage, type Message } from './chat-message'

afterEach(cleanup)

describe('workflow response', () => {
  const message: Message = {
    id: 'workflow', role: 'assistant', content: 'I will analyze the attached structures.', timestamp: new Date(),
    metadata: { type: 'workflow', workflow: { name: 'ADMET screen' } },
  }

  it('shows intent and unfolded updates within the same assistant response', () => {
    const { container } = render(<ChatMessage message={message} isInPanel progressMessages={[
      { id: 'progress', role: 'assistant', content: 'Input structures resolved.', timestamp: new Date() },
    ]} />)
    expect(screen.getByText(message.content)).toBeVisible()
    expect(screen.getByRole('log')).toHaveTextContent(message.content)
    expect(screen.getByRole('log')).toHaveTextContent('Input structures resolved.')
    expect(screen.getByRole('log').closest('[data-testid="chat-message-workflow"]')).not.toBeNull()
    expect(container.querySelector('details')).toBeNull()
    expect(screen.queryByText('Analysis plan')).toBeNull()
  })

  it('keeps the answer visible without repeating the assistant identity', () => {
    render(<ChatMessage continuation message={{ ...message, id: 'findings', content: 'Aspirin and caffeine exceed the DILI threshold.', metadata: { type: 'findings' } }} />)
    expect(screen.getByText('Aspirin and caffeine exceed the DILI threshold.')).toBeVisible()
    expect(screen.queryByText('BioMate')).toBeNull()
  })

  it('streams the complete growing plan with its formatting and source links', () => {
    const { rerender } = render(<ChatMessage message={message} isStreaming isInPanel />)
    const content = '**Resolve the inputs.**\n\nThen inspect every compound.\n\n[Input file](https://example.org/inputs)'
    rerender(<ChatMessage message={{ ...message, content }} isStreaming isInPanel />)
    const log = screen.getByRole('log')
    expect(log).toHaveTextContent('Resolve the inputs.')
    expect(log).toHaveTextContent('Then inspect every compound.')
    expect(log.querySelector('strong')).toHaveTextContent('Resolve the inputs.')
    expect(screen.getByRole('link', { name: 'Input file' }).closest('[role="log"]')).toBe(log)
    expect(screen.queryByText('Writing response…')).toBeNull()
    expect(screen.queryByText('Analysis plan')).toBeNull()
  })

  it('leaves response controls with the final answer and removes redundant run hints', () => {
    render(<ChatMessage message={message} isInPanel hideActions currentExecutionRun={{
      id: 'run-a', execution: { status: 'completed' },
    } as any} />)
    expect(screen.getByText('Completed')).toBeVisible()
    expect(screen.queryByTestId('button-copy-response-icon')).toBeNull()
    expect(screen.queryByTestId('wf-chip-background-hint')).toBeNull()
  })
})
