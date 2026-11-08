import { describe, it, expect } from 'vitest'
import { entityOrdinals, displayInterp } from './findings-card'
import type { LegacyKeyResult } from '@shared/findings'

// Regression guard: a per-compound ADMET finding identifies its entity by a raw
// SMILES, which contains NESTED parentheses. The Interpretation column must show
// a short "(Compound N)" ordinal with the SMILES stripped WHOLE — an earlier
// regex stopped at the first ")" and left a SMILES fragment in the prose
// (e.g. "(Compound 1) OC1=CC=CC=C1C(=O)O) Acceptable…"). Verified on dev
// 2026-10-28 before this guard.

const aspirin = 'CC(=O)OC1=CC=CC=C1C(=O)O'
const diphenyl = 'OC(c1ccccc1)c1ccccc1'

describe('findings-card entity ordinals + SMILES stripping', () => {
  it('maps distinct SMILES entities to Compound N ordinals', () => {
    const rows: LegacyKeyResult[] = [
      { metric: 'hERG', value: '0.003', interpretation: `(${aspirin}) Acceptable risk`, entity: aspirin },
      { metric: 'hERG', value: '0.21', interpretation: `(${diphenyl}) Elevated risk`, entity: diphenyl },
    ]
    const ord = entityOrdinals(rows)
    expect(ord.get(aspirin)).toBe('Compound 1')
    expect(ord.get(diphenyl)).toBe('Compound 2')
  })

  it('strips a SMILES prefix with nested parens WHOLE and keeps the rest', () => {
    const ord = entityOrdinals([{ metric: 'hERG', value: '0.003', interpretation: `(${aspirin}) Acceptable hERG (cardiac) risk (0.003)`, entity: aspirin }])
    const { label, text, title } = displayInterp(
      { metric: 'hERG', value: '0.003', interpretation: `(${aspirin}) Acceptable hERG (cardiac) risk (0.003)`, entity: aspirin },
      ord,
    )
    expect(label).toBe('Compound 1')
    // The leading SMILES group is removed entirely; later parentheticals survive.
    expect(text).toBe('Acceptable hERG (cardiac) risk (0.003)')
    expect(text).not.toContain(aspirin)
    expect(text).not.toMatch(/^\)/) // no dangling ")" fragment
    expect(title).toBe(aspirin) // full SMILES preserved on hover
  })

  it('derives the identity from the prose prefix when entity is unset', () => {
    const rows: LegacyKeyResult[] = [{ metric: 'LogP', value: '2.1', interpretation: `(${aspirin}) within range` }]
    const ord = entityOrdinals(rows)
    const { label, text } = displayInterp(rows[0], ord)
    expect(label).toBe('Compound 1')
    expect(text).toBe('within range')
  })

  it('leaves a non-entity interpretation untouched', () => {
    const rows: LegacyKeyResult[] = [{ metric: 'Total', value: '5', interpretation: 'Five compounds ranked' }]
    const ord = entityOrdinals(rows)
    const { label, text } = displayInterp(rows[0], ord)
    expect(label).toBeUndefined()
    expect(text).toBe('Five compounds ranked')
  })

  it('keeps an already-short ordinal label as-is', () => {
    const rows: LegacyKeyResult[] = [{ metric: 'hERG', value: '0.003', interpretation: '(Compound 1) ok', entity: 'Compound 1' }]
    const ord = entityOrdinals(rows)
    expect(ord.get('Compound 1')).toBe('Compound 1')
    const { title } = displayInterp(rows[0], ord)
    expect(title).toBeUndefined() // not shortened, no hover needed
  })
})
