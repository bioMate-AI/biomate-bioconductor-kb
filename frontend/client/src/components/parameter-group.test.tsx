/**
 * RTL tests for <ParameterGroup> — §7.4 parameter-origin taxonomy badges.
 * Every param row must carry exactly one origin badge; derivation is honest
 * (unknown provenance falls back to "default").
 *
 * Also covers storage-URI redaction in Workflow settings (2026-11-13 Admet Pred
 * incident): Inputs show cleanParamValueForDisplay, form state keeps real s3://.
 */
import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import {
  ParameterGroup,
  deriveParamOrigin,
  paramValueForDisplay,
  isStorageParamValue,
  type Parameter,
} from './parameter-group'

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

describe('paramValueForDisplay / storage redaction', () => {
  const S3 =
    's3://biomate-nextflow-work/uploads/0238d454-8be2-42db-9bc7-9e76e274f317/candidate_library.csv'

  it('detects storage URIs and shows only the file name', () => {
    expect(isStorageParamValue(S3)).toBe(true)
    expect(paramValueForDisplay(S3)).toBe('candidate_library.csv')
    expect(paramValueForDisplay(S3)).not.toMatch(/s3:\/\//i)
    expect(paramValueForDisplay('plain SMILES')).toBe('plain SMILES')
  })

  it('Workflow settings Inputs never paint raw s3://; form state keeps the URI until Browse', () => {
    const onChange = vi.fn()
    render(
      <ParameterGroup
        id="settings"
        title="Workflow settings"
        defaultOpen
        onChange={onChange}
        parameters={[
          mk({
            id: 'library_file',
            label: 'Library File',
            type: 'file',
            value: S3,
            autoFilled: true,
          }),
        ]}
      />,
    )
    const input = screen.getByTestId('param-input-library_file') as HTMLInputElement
    expect(input.value).toBe('candidate_library.csv')
    expect(input.value).not.toMatch(/s3:\/\//i)
    expect(input).toHaveAttribute('data-storage-redacted', '1')
    expect(input).toHaveAttribute('readOnly')
    // Typing must not clobber the real s3 URI held in parent state.
    fireEvent.change(input, { target: { value: 'hacked.csv' } })
    expect(onChange).not.toHaveBeenCalled()
  })

  it('non-storage string values remain editable and pass through onChange', () => {
    const onChange = vi.fn()
    render(
      <ParameterGroup
        id="settings2"
        title="Workflow settings"
        defaultOpen
        onChange={onChange}
        parameters={[mk({ id: 'model_type', label: 'Model type', type: 'string', value: 'MPNN' })]}
      />,
    )
    const input = screen.getByTestId('param-input-model_type') as HTMLInputElement
    expect(input.value).toBe('MPNN')
    fireEvent.change(input, { target: { value: 'RF' } })
    expect(onChange).toHaveBeenCalledWith('model_type', 'RF')
  })
})
