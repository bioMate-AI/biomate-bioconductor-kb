/**
 * Unit Tests: PipelineListView — S4 Step-by-Step Approval Gate
 *
 * Tests that approvalGate mode:
 * 1. Shows "Confirm & Run Step 1" (not "Run Pipeline") when pipeline hasn't started
 * 2. Shows "Approve & Run Step N+1" button under a completed step
 * 3. Hides the footer "Confirm & Run" button once the pipeline is running
 * 4. Calls onApproveStep(completedId, nextId) when the approve button is clicked
 */

import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { PipelineListView, PipelineStep } from './pipeline-list-view'

const makeStep = (overrides: Partial<PipelineStep> & { id: string }): PipelineStep => ({
  workflowName: overrides.id,
  params: {},
  status: 'pending',
  stepNumber: 1,
  ...overrides,
})

const STEPS_PENDING: PipelineStep[] = [
  makeStep({ id: 's1', stepNumber: 1, workflowName: 'ADMET Screen', status: 'pending' }),
  makeStep({ id: 's2', stepNumber: 2, workflowName: 'Docking', status: 'pending' }),
  makeStep({ id: 's3', stepNumber: 3, workflowName: 'MD Simulation', status: 'pending' }),
]

const STEPS_S1_COMPLETE: PipelineStep[] = [
  makeStep({ id: 's1', stepNumber: 1, workflowName: 'ADMET Screen', status: 'completed' }),
  makeStep({ id: 's2', stepNumber: 2, workflowName: 'Docking', status: 'pending' }),
  makeStep({ id: 's3', stepNumber: 3, workflowName: 'MD Simulation', status: 'pending' }),
]

describe('PipelineListView — S4 approval gate', () => {
  it('without approvalGate: shows "Confirm & Run Pipeline" button', () => {
    render(<PipelineListView steps={STEPS_PENDING} />)
    expect(screen.getByTestId('pipeline-confirm-run')).toHaveTextContent('Confirm & Run Pipeline')
  })

  it('approvalGate + all pending: shows "Confirm & Run Step 1" button', () => {
    render(<PipelineListView steps={STEPS_PENDING} approvalGate />)
    expect(screen.getByTestId('pipeline-confirm-run')).toHaveTextContent('Confirm & Run Step 1')
  })

  it('approvalGate + step 1 complete: shows approve button for step 2', () => {
    render(<PipelineListView steps={STEPS_S1_COMPLETE} approvalGate />)
    expect(screen.getByTestId('pipeline-approve-step-s2')).toBeInTheDocument()
    expect(screen.getByTestId('pipeline-approve-step-s2')).toHaveTextContent('Approve & Run Step 2')
  })

  it('approvalGate + step 1 complete: does NOT show approve button for step 3 yet', () => {
    render(<PipelineListView steps={STEPS_S1_COMPLETE} approvalGate />)
    expect(screen.queryByTestId('pipeline-approve-step-s3')).not.toBeInTheDocument()
  })

  it('approvalGate + pipeline started: hides the footer confirm button', () => {
    render(<PipelineListView steps={STEPS_S1_COMPLETE} approvalGate />)
    // Pipeline has started (s1=completed), confirm-run button should be gone
    expect(screen.queryByTestId('pipeline-confirm-run')).not.toBeInTheDocument()
  })

  it('approvalGate: footer shows "Awaiting step approval…" when pipeline started', () => {
    render(<PipelineListView steps={STEPS_S1_COMPLETE} approvalGate />)
    expect(screen.getByText('Awaiting step approval…')).toBeInTheDocument()
  })

  it('onApproveStep is called with (completedId, nextId) when approve button clicked', () => {
    const onApproveStep = vi.fn()
    render(<PipelineListView steps={STEPS_S1_COMPLETE} approvalGate onApproveStep={onApproveStep} />)
    fireEvent.click(screen.getByTestId('pipeline-approve-step-s2'))
    expect(onApproveStep).toHaveBeenCalledOnce()
    expect(onApproveStep).toHaveBeenCalledWith('s1', 's2')
  })

  it('without approvalGate: no approve buttons even when a step is completed', () => {
    render(<PipelineListView steps={STEPS_S1_COMPLETE} approvalGate={false} />)
    expect(screen.queryByTestId('pipeline-approve-step-s2')).not.toBeInTheDocument()
  })

  it('approvalGate: step 2 running — no approve button shown (not pending)', () => {
    const steps: PipelineStep[] = [
      makeStep({ id: 's1', stepNumber: 1, workflowName: 'ADMET Screen', status: 'completed' }),
      makeStep({ id: 's2', stepNumber: 2, workflowName: 'Docking', status: 'running' }),
      makeStep({ id: 's3', stepNumber: 3, workflowName: 'MD Simulation', status: 'pending' }),
    ]
    render(<PipelineListView steps={steps} approvalGate />)
    // s2 is running — no approve-s3 button yet
    expect(screen.queryByTestId('pipeline-approve-step-s3')).not.toBeInTheDocument()
  })
})
