/**
 * RegisterModelForm — the connector "A model" flow registers a hosted REST scorer.
 * No msw: fetch is mocked at the boundary; we assert the real POST body + success UI.
 */
import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { RegisterModelForm } from './register-model-form';

vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast: () => {} }) }));

beforeEach(() => { vi.restoreAllMocks(); });

describe('RegisterModelForm', () => {
  it('submit is gated until a name and an http(s) endpoint are given', () => {
    render(<RegisterModelForm />);
    const submit = () => screen.getByTestId('register-model-submit') as HTMLButtonElement;
    expect(submit().disabled).toBe(true);
    fireEvent.change(screen.getByTestId('register-model-name'), { target: { value: 'My scorer' } });
    expect(submit().disabled).toBe(true); // no endpoint yet
    fireEvent.change(screen.getByTestId('register-model-endpoint'), { target: { value: 'not-a-url' } });
    expect(submit().disabled).toBe(true); // not http(s)
    fireEvent.change(screen.getByTestId('register-model-endpoint'), { target: { value: 'https://m.example.com/score' } });
    expect(submit().disabled).toBe(false);
  });

  it('POSTs the registration and shows the registered state', async () => {
    const calls: any[] = [];
    global.fetch = vi.fn(async (url: any, init?: any) => {
      calls.push({ url: String(url), body: JSON.parse(init?.body || '{}') });
      return { ok: true, status: 200, json: async () => ({ id: 'custom:connector-models-u1/My scorer', name: 'My scorer', family: 'rest' }) } as any;
    }) as unknown as typeof fetch;

    render(<RegisterModelForm />);
    fireEvent.change(screen.getByTestId('register-model-name'), { target: { value: 'My scorer' } });
    fireEvent.change(screen.getByTestId('register-model-endpoint'), { target: { value: 'https://m.example.com/score' } });
    fireEvent.click(screen.getByTestId('register-model-submit'));

    await waitFor(() => expect(screen.getByTestId('register-model-done')).toBeTruthy());
    expect(calls[0].url).toContain('/api/models/register-external');
    expect(calls[0].body).toMatchObject({ name: 'My scorer', endpoint: 'https://m.example.com/score', input_key: 'smiles', output_path: 'scores' });
  });

  it('surfaces a backend error instead of a silent failure', async () => {
    global.fetch = vi.fn(async () => ({ ok: false, status: 400, json: async () => ({ detail: 'endpoint must be an http(s) URL we can call for scoring' }) } as any)) as unknown as typeof fetch;
    render(<RegisterModelForm />);
    fireEvent.change(screen.getByTestId('register-model-name'), { target: { value: 'X' } });
    fireEvent.change(screen.getByTestId('register-model-endpoint'), { target: { value: 'https://x.example.com' } });
    fireEvent.click(screen.getByTestId('register-model-submit'));
    await waitFor(() => expect(screen.getByTestId('register-model-error').textContent).toContain('http(s) URL'));
  });
});
