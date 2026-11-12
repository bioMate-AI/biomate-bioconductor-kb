import { describe, it, expect, vi } from 'vitest'

// originLabel maps a backend origin code to a localized label; use the fallback
// identity so the test asserts the code→key mapping, not the translation bundle.
vi.mock('@/lib/i18n', () => ({
  t: (key: string) => key,
  tOr: (_key: string, fallback: string) => fallback,
}))

import { originLabel } from './model-origin'

describe('originLabel — honest model execution origin', () => {
  it('maps aws_batch to its own label (Boltz-2 runs on BioMate compute, not NVIDIA)', () => {
    expect(originLabel('aws_batch')).toBe('models.origin_aws_batch')
  })
  it('still maps the real BioNeMo-client modes', () => {
    expect(originLabel('hosted_nvidia')).toBe('models.origin_hosted_nvidia')
    expect(originLabel('self_host')).toBe('models.origin_self_host')
  })
  it('renders an unknown code verbatim and empty as unconfigured', () => {
    expect(originLabel('something_else')).toBe('something_else')
    expect(originLabel('')).toBe('Not configured')
    expect(originLabel(null)).toBe('Not configured')
  })
})
