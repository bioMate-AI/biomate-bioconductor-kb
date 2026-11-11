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
it('renders blocked and submitting states without treating them as pending', () => {
  render(<PipelineListView steps={[
    makeStep({ id: 'blocked', status: 'blocked', errorMessage: 'Upstream failed' }),
    makeStep({ id: 'submitting', status: 'submitting' }),
  ]} />)
  expect(screen.getByText('BLOCKED')).toBeInTheDocument()
  expect(screen.getByText('SUBMITTING')).toBeInTheDocument()
  expect(screen.getByText(/Upstream failed/)).toBeInTheDocument()
})
it('shows whole-plan scope, dependencies and case identities before submission', () => {
  const onConfirmRun = vi.fn()
  render(<PipelineListView steps={[
    makeStep({ id: 'a', dependsOn: [], dimensions: { target: 'A' } }),
    makeStep({ id: 'b', dependsOn: [1] }),
  ]} onConfirmRun={onConfirmRun} />)
  expect(screen.getByText(/Confirm to run all steps/)).toBeInTheDocument()
  expect(screen.getByText('Requires steps 1')).toBeInTheDocument()
  expect(screen.getByText('target: A')).toBeInTheDocument()
  fireEvent.click(screen.getByTestId('pipeline-confirm-run'))
  expect(onConfirmRun).toHaveBeenCalledOnce()
})
it('shows partial parent status without allowing resubmission of the same graph', () => {
  render(<PipelineListView steps={[makeStep({ id: 'a', dependsOn: [], status: 'failed' })]}
    chainRunId="existing" chainStatus="partial" />)
  expect(screen.getByTestId('pipeline-parent-status')).toHaveTextContent('partial')
  expect(screen.queryByTestId('pipeline-confirm-run')).not.toBeInTheDocument()
})

// P2 (2026-11-11): a decomposed plan step says what runs, what it waits on, and what is still needed
// — the demo card showed steps with no inputs and no hint (looked empty).
describe('PipelineListView — plan step inputs', () => {
  const PLAN: PipelineStep[] = [
    makeStep({ id: 'p1', stepNumber: 1, workflowName: 'Adapt the generator to our series',
      resolution: 'catalog_workflow', workflowLabel: 'Reinvent4 Finetune Rl', missingInputs: ['train_smiles'] }),
    makeStep({ id: 'p2', stepNumber: 2, workflowName: 'Rank the generated molecules',
      workflowLabel: 'rank_candidates', dependsOn: [1], needsInputMapping: true }),
    makeStep({ id: 'p3', stepNumber: 3, workflowName: 'Plain step' }),
  ]

  it('names the workflow each step runs', () => {
    render(<PipelineListView steps={PLAN} />)
    expect(screen.getByTestId('plan-step-runs-p1').textContent).toMatch(/Reinvent4 Finetune Rl.*catalog workflow/)
    expect(screen.queryByTestId('plan-step-runs-p3')).toBeNull() // no label → no line (other cards unchanged)
  })

  it('says which inputs are still needed instead of rendering an empty step', () => {
    render(<PipelineListView steps={PLAN} />)
    expect(screen.getByTestId('plan-step-needs-p1').textContent).toContain('train_smiles')
    expect(screen.getByTestId('plan-step-needs-p2').textContent).toMatch(/Map inputs from earlier steps/)
    expect(screen.queryByTestId('plan-step-needs-p3')).toBeNull()
  })

  it('shows what a step waits on', () => {
    render(<PipelineListView steps={PLAN} />)
    expect(screen.getByTestId('plan-step-after-p2')).toBeTruthy()
    expect(screen.queryByTestId('plan-step-after-p1')).toBeNull()
  })

  it('drops the needed-inputs hint once the step is no longer pending', () => {
    render(<PipelineListView steps={[{ ...PLAN[0], status: 'running' }]} />)
    expect(screen.queryByTestId('plan-step-needs-p1')).toBeNull()
  })
})
