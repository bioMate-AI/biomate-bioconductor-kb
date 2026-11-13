import { describe, expect, it } from 'vitest'
import { licenseGatePathForWorkflow, pathImpliesHardLicenseGate } from './license-gate'

describe('pathImpliesHardLicenseGate', () => {
  it('detects cryosparc and other BYOL tools in the path', () => {
    expect(pathImpliesHardLicenseGate('cryosparc_standard_spa/main.nf')).toBe(true)
    expect(pathImpliesHardLicenseGate('/workflows/alphafold3/main.nf')).toBe(true)
    expect(pathImpliesHardLicenseGate('nf-core/rnaseq/main.nf')).toBe(false)
  })
})

describe('licenseGatePathForWorkflow', () => {
  it('prefers an explicit nextflow_path', () => {
    expect(licenseGatePathForWorkflow({
      nextflow_path: 'foo/cryosparc_standard_spa/main.nf',
      name: 'Cryosparc Standard Spa',
    })).toBe('foo/cryosparc_standard_spa/main.nf')
  })

  it('synthesizes a cryosparc path when only workflow_type/name is set', () => {
    expect(licenseGatePathForWorkflow({
      name: 'Cryosparc Standard Spa',
      workflow_type: 'cryosparc',
    })).toBe('cryosparc_standard_spa/main.nf')
  })

  it('returns null for ordinary workflows without a path', () => {
    expect(licenseGatePathForWorkflow({ name: 'RNA-seq' })).toBeNull()
  })
})
