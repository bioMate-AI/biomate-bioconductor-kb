import { expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
vi.mock('3dmol', () => ({ default: {}, GLViewer: class {}, createViewer: () => ({}) }))
import { ChatMessage, type Message } from './chat-message'

it.each([true, false])('wires the correct approval mode for explicit graph=%s', async graph => {
  const workflow = { workflow_type: 'pipeline', name: 'Comparison', pipeline_steps: [
    { workflow_name: 'First', ...(graph ? { depends_on: [], dimensions: { target: 'A' } } : {}) },
    { workflow_name: 'Second', ...(graph ? { depends_on: [1] } : {}) },
  ] }
  const onRunPipeline = vi.fn()
  const { container } = render(<ChatMessage message={{ id: 'approval', role: 'assistant', content: '', timestamp: new Date(),
    metadata: { type: 'workflow', workflow } } as Message} onRunPipeline={onRunPipeline} />)
  // Inline PipelineListView representation renders one row per step (data-testid
  // pipeline-step-<id>), excluding the per-step remove buttons (pipeline-step-remove-<id>).
  expect(screen.getByTestId('pipeline-list-view')).toBeInTheDocument()
  const stepRows = container.querySelectorAll(
    '[data-testid^="pipeline-step-"]:not([data-testid^="pipeline-step-remove-"])',
  )
  expect(stepRows.length).toBe(workflow.pipeline_steps.length)
  const button = screen.getByTestId('pipeline-confirm-run')
  expect(button).toHaveTextContent(graph ? 'Confirm & Run Pipeline' : 'Confirm & Run Step 1')
  await userEvent.click(button)
  expect(onRunPipeline).toHaveBeenCalledWith(workflow)
})
