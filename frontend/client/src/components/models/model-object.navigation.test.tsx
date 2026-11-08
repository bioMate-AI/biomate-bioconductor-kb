import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { ModelObjectLoader } from './model-object';
vi.mock('./models-api', () => ({ useModel: () => ({ isLoading: true, isError: false }) }));
vi.mock('@/lib/i18n', () => ({ tOr: (_key: string, fallback: string) => fallback }));
describe('model detail navigation', () => {
  it('allows returning to the registry while model loading is pending', () => {
    const back = vi.fn();
    render(<ModelObjectLoader modelId="slow-model" onBack={back} />);
    fireEvent.click(screen.getByRole('button', { name: 'Back' }));
    expect(back).toHaveBeenCalledOnce();
  });
});
