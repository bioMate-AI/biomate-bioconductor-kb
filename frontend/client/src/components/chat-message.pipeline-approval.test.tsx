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
  render(<ChatMessage message={{ id: 'approval', role: 'assistant', content: '', timestamp: new Date(),
    metadata: { type: 'workflow', workflow } } as Message} onRunPipeline={onRunPipeline} />)
  const button = screen.getByTestId('pipeline-confirm-run')
  expect(button).toHaveTextContent(graph ? 'Confirm & Run Pipeline' : 'Confirm & Run Step 1')
  await userEvent.click(button)
  expect(onRunPipeline).toHaveBeenCalledWith(workflow)
})
