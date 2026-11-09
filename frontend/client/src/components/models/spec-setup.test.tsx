import { afterEach, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { SpecSetup } from './spec-setup';

const setProject = vi.fn();
vi.mock('@/contexts/active-project-context', () => ({
  useActiveProjectSafe: () => ({ activeProjectId: 'project-1', projects: [{ id: 'project-1', name: 'Research' }], setActiveProjectId: setProject }),
}));
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

function stubFiles(name: string) {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => ({ files: [{ id: 'f1', name }] }) }));
}

it('protein-diffusion panel renders its spec fields and submits a structure_generation request', async () => {
  stubFiles('backbones.pdb');
  const next = vi.fn();
  render(<SpecSetup initialType="protein_diffusion" onContinue={next} />);
  await waitFor(() => expect(screen.getByText('backbones.pdb')).toBeInTheDocument());
  // Spec-specific fields are rendered (not the classification form).
  expect(screen.getByLabelText('Number of designs')).toHaveValue(8);
  expect(screen.getByLabelText('Length min (residues)')).toHaveValue(60);
  expect(screen.getByLabelText('Structure set (PDB/mmCIF backbones)')).toBeInTheDocument();
  fireEvent.change(screen.getByLabelText('Structure set (PDB/mmCIF backbones)'), { target: { value: 'f1' } });
  fireEvent.click(screen.getByText('Review in chat'));
  expect(next).toHaveBeenCalledOnce();
  const draft = new URL(next.mock.calls[0][0], 'https://example.test').searchParams.get('draft') ?? '';
  expect(draft).toContain('model_type=protein_diffusion');
  expect(draft).toContain('task_type=structure_generation');
  expect(draft).toContain('framework=rfdiffusion');
  expect(draft).toContain('num_designs=8');
  expect(draft).toContain('before execution');
  expect(draft).toContain('file ID f1');
});

it('scrna-diffusion panel submits an expression_generation request (train-from-scratch avoids the warm-start gate)', async () => {
  stubFiles('cells.h5ad');
  const next = vi.fn();
  render(<SpecSetup initialType="scrna_diffusion" onContinue={next} />);
  await waitFor(() => expect(screen.getByText('cells.h5ad')).toBeInTheDocument());
  expect(screen.getByLabelText('Cells to generate')).toHaveValue(1000);
  fireEvent.change(screen.getByLabelText('Single-cell data (h5ad AnnData)'), { target: { value: 'f1' } });
  // Default finetune=true with empty checkpoints is invalid (mirrors SCDiffusionSpec.validate),
  // so the submit is gated until we uncheck fine-tune (train from scratch).
  expect(screen.getByText('Review in chat').closest('button')).toBeDisabled();
  fireEvent.click(screen.getByRole('checkbox'));
  fireEvent.click(screen.getByText('Review in chat'));
  expect(next).toHaveBeenCalledOnce();
  const draft = new URL(next.mock.calls[0][0], 'https://example.test').searchParams.get('draft') ?? '';
  expect(draft).toContain('model_type=scrna_diffusion');
  expect(draft).toContain('task_type=expression_generation');
  expect(draft).toContain('framework=scdiffusion');
  expect(draft).toContain('finetune=false');
});

it('tabular-diffusion panel submits a tabular_generation request (train-from-scratch avoids the warm-start gate)', async () => {
  stubFiles('features.csv');
  const next = vi.fn();
  render(<SpecSetup initialType="tabular_diffusion" onContinue={next} />);
  await waitFor(() => expect(screen.getByText('features.csv')).toBeInTheDocument());
  expect(screen.getByLabelText('Rows to generate')).toHaveValue(1000);
  fireEvent.change(screen.getByLabelText('Tabular data (CSV/parquet feature matrix)'), { target: { value: 'f1' } });
  // Default finetune=true with an empty checkpoint is invalid (mirrors TabularDiffusionSpec.validate),
  // so the submit is gated until we uncheck fine-tune (train from scratch).
  expect(screen.getByText('Review in chat').closest('button')).toBeDisabled();
  fireEvent.click(screen.getByRole('checkbox'));
  fireEvent.click(screen.getByText('Review in chat'));
  expect(next).toHaveBeenCalledOnce();
  const draft = new URL(next.mock.calls[0][0], 'https://example.test').searchParams.get('draft') ?? '';
  expect(draft).toContain('model_type=tabular_diffusion');
  expect(draft).toContain('task_type=tabular_generation');
  expect(draft).toContain('framework=tabddpm');
  expect(draft).toContain('finetune=false');
});

it('LLM (ludwig_llm) panel submits a text_generation request with a random split', async () => {
  stubFiles('instructions.jsonl');
  const next = vi.fn();
  render(<SpecSetup initialType="ludwig_llm" onContinue={next} />);
  await waitFor(() => expect(screen.getByText('instructions.jsonl')).toBeInTheDocument());
  expect(screen.getByLabelText('Base model (HF id)')).toHaveValue('HuggingFaceTB/SmolLM2-135M-Instruct');
  expect(screen.getByLabelText('Instruction column')).toHaveValue('instruction');
  fireEvent.change(screen.getByLabelText('Training data (JSONL/CSV: instruction, output)'), { target: { value: 'f1' } });
  fireEvent.click(screen.getByText('Review in chat'));
  const draft = new URL(next.mock.calls[0][0], 'https://example.test').searchParams.get('draft') ?? '';
  expect(draft).toContain('model_type=ludwig_llm');
  expect(draft).toContain('task_type=text_generation');
  expect(draft).toContain('split=random');
  expect(draft).toContain('adapter=lora');
});

it('GRPO reward=keyword gates submit until a keyword is provided', async () => {
  stubFiles('prompts.jsonl');
  const next = vi.fn();
  render(<SpecSetup initialType="trl_grpo" onContinue={next} />);
  await waitFor(() => expect(screen.getByText('prompts.jsonl')).toBeInTheDocument());
  fireEvent.change(screen.getByLabelText('Prompts (JSONL/CSV: prompt)'), { target: { value: 'f1' } });
  fireEvent.change(screen.getByLabelText('Reward function'), { target: { value: 'keyword' } });
  expect(screen.getByText('Review in chat').closest('button')).toBeDisabled();
  fireEvent.change(screen.getByLabelText('Reward keyword'), { target: { value: 'dose' } });
  fireEvent.click(screen.getByText('Review in chat'));
  const draft = new URL(next.mock.calls[0][0], 'https://example.test').searchParams.get('draft') ?? '';
  expect(draft).toContain('model_type=trl_grpo');
  expect(draft).toContain('reward=keyword');
  expect(draft).toContain('reward_keyword=dose');
});
