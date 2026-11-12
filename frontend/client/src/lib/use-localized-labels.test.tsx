import { afterEach, describe, expect, it, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { useLocalizedLabels, _resetLocalizedLabelCache } from './use-localized-labels';

afterEach(() => { _resetLocalizedLabelCache(); vi.restoreAllMocks(); });

describe('useLocalizedLabels', () => {
  it('is the identity outside zh and makes no request', () => {
    const f = vi.spyOn(global, 'fetch');
    const { result } = renderHook(() => useLocalizedLabels(['Input Download'], 'en'));
    expect(result.current('Input Download')).toBe('Input Download');
    expect(f).not.toHaveBeenCalled();
  });
  it('under zh renders the source first, then the translation', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(async () => ({
      ok: true, json: async () => ({ translations: { 'Input Download': '读取输入数据' } }),
    } as Response));
    const { result } = renderHook(() => useLocalizedLabels(['Input Download'], 'zh'));
    expect(result.current('Input Download')).toBe('Input Download');
    await waitFor(() => expect(result.current('Input Download')).toBe('读取输入数据'));
  });
  it('a failed request leaves the source text', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(async () => { throw new Error('offline'); });
    const { result } = renderHook(() => useLocalizedLabels(['Normalisation'], 'zh'));
    await waitFor(() => expect(result.current('Normalisation')).toBe('Normalisation'));
  });
});
