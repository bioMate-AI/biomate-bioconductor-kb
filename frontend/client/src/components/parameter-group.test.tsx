/**
 * RTL tests for <ParameterGroup> — §7.4 parameter-origin taxonomy badges.
 * Every param row must carry exactly one origin badge; derivation is honest
 * (unknown provenance falls back to "default").
 */
import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { ParameterGroup, deriveParamOrigin, type Parameter } from './parameter-group'

function mk(partial: Partial<Parameter>): Parameter {
  return {
    id: partial.id || 'p1',
    name: partial.name || 'p1',
    type: partial.type || 'string',
    label: partial.label || 'Param',
    ...partial,
  }
}

describe('deriveParamOrigin', () => {
  it('maps each flag to its origin flavor', () => {
    expect(deriveParamOrigin(mk({ overridden: true }))).toBe('edited')
    expect(deriveParamOrigin(mk({ confirmed: true }))).toBe('confirmed')
    expect(deriveParamOrigin(mk({ autoFilled: true }))).toBe('recommended')
    expect(deriveParamOrigin(mk({ inherited: true }))).toBe('inherited')
    expect(deriveParamOrigin(mk({}))).toBe('default')
  })

  it('prefers a user edit over any prior origin', () => {
    expect(deriveParamOrigin(mk({ overridden: true, autoFilled: true, confirmed: true }))).toBe('edited')
    expect(deriveParamOrigin(mk({ confirmed: true, autoFilled: true }))).toBe('confirmed')
  })
})

describe('<ParameterGroup> origin badges', () => {
  const params: Parameter[] = [
    mk({ id: 'a', label: 'A default' }),
    mk({ id: 'b', label: 'B recommended', autoFilled: true }),
    mk({ id: 'c', label: 'C edited', overridden: true }),
    mk({ id: 'd', label: 'D inherited', inherited: true }),
    mk({ id: 'e', label: 'E confirmed', confirmed: true }),
    mk({ id: 'f', label: 'F boolean', type: 'boolean', autoFilled: true }),
  ]

  it('renders exactly one origin badge per param with the correct label + data-origin', () => {
    render(<ParameterGroup id="grp" title="Params" parameters={params} defaultOpen />)
    const cases: Array<[string, string, string]> = [
      ['a', 'default', 'Default'],
      ['b', 'recommended', 'Recommended'],
      ['c', 'edited', 'Edited'],
      ['d', 'inherited', 'Inherited'],
      ['e', 'confirmed', 'Confirmed'],
      ['f', 'recommended', 'Recommended'],
    ]
    for (const [id, origin, label] of cases) {
      const badge = screen.getByTestId(`param-origin-badge-${id}`)
      expect(badge).toBeInTheDocument()
      expect(badge).toHaveAttribute('data-origin', origin)
      expect(badge).toHaveTextContent(label)
    }
  })

  it('badges the boolean-type row too', () => {
    render(<ParameterGroup id="grp2" title="Params" parameters={[params[5]]} defaultOpen />)
    expect(screen.getByTestId('param-origin-badge-f')).toHaveAttribute('data-origin', 'recommended')
  })
})
