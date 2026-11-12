/**
 * Chat tool card — what the user sees for an agent tool call.
 * Live cases from the founder's screenshots (dev 2026-11-12): a read_file card
 * showed `{"galaxy_dataset_id":"<uuid>"}`, and the collapsed code preview cut its
 * second line in half.
 */
import React from 'react';
import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { CodeExecutionBlock, codePreview } from './code-execution-block';

const UUID = 'b9ce582c-fded-4db5-838f-bdd96820f72c';

describe('CodeExecutionBlock', () => {
  it('read_file shows the server display name — never the raw input', () => {
    const { container } = render(<CodeExecutionBlock block={{
      tool_use_id: 't1', name: 'read_file',
      call: { type: 'tool_call', tool_use_id: 't1', name: 'read_file', input: { galaxy_dataset_id: UUID }, display: '0.jpeg' },
      result: { type: 'tool_result', tool_use_id: 't1', name: 'read_file', output: { message: 'ok' }, duration_ms: 300 },
    }} />);
    expect(screen.getByTestId('tool-input-summary').textContent).toBe('0.jpeg');
    fireEvent.click(screen.getByRole('button', { expanded: false }));
    expect(container.textContent).not.toMatch(/galaxy|b9ce582c/i);
  });

  it('an older message without display: the id is dropped, not shown', () => {
    const { container } = render(<CodeExecutionBlock block={{
      tool_use_id: 't2', name: 'read_file',
      call: { type: 'tool_call', tool_use_id: 't2', name: 'read_file', input: { galaxy_dataset_id: UUID } },
    }} />);
    expect(screen.queryByTestId('tool-input-summary')).toBeNull();
    fireEvent.click(screen.getByRole('button', { expanded: false }));
    expect(container.textContent).not.toMatch(/galaxy|b9ce582c/i);
  });

  it('collapsed code preview: leading blank line dropped, two whole lines, remainder counted below', () => {
    const code = '\nfrom PIL import Image\nimport os\nimport numpy as np\nprint(1)\n';
    expect(codePreview(code)).toEqual({ lines: ['from PIL import Image', 'import os'], more: 2 });
    render(<CodeExecutionBlock block={{
      tool_use_id: 't3', name: 'run_code',
      call: { type: 'tool_call', tool_use_id: 't3', name: 'run_code', input: { code, language: 'python' } },
    }} />);
    const preview = screen.getByTestId('tool-code-preview');
    expect(preview.querySelector('pre')!.textContent).toBe('from PIL import Image\nimport os');
    expect(preview.querySelector('pre')!.className).not.toMatch(/max-h-/);
    expect(preview.textContent).toContain('+2 more lines');
  });
});
