import { describe, expect, it } from 'vitest'
import {
  buildChainConnections,
  buildChainSubmitSteps,
} from './chain-execution'

describe('buildChainSubmitSteps', () => {
  it('maps curated chain steps to submit payload', () => {
    const steps = buildChainSubmitSteps([
      {
        order: 1,
        workflow_name: 'predict_admet_properties',
        nextflow_path: 'nextflow_nfcore/subworkflows/drug_discovery/predict_admet_properties/main.nf',
        params_template: { profile: 'druglike_lead' },
      },
    ])
    expect(steps[0].nextflow_path).toContain('predict_admet_properties')
    expect(steps[0].params).toEqual({ profile: 'druglike_lead' })
  })

  it('accepts pipeline_steps shape from Tier 2 assistant', () => {
    const steps = buildChainSubmitSteps([
      {
        workflow_name: 'nf-core/rnaseq',
        nextflowPath: 'nfcore/rnaseq/main.nf',
        params: { genome: 'GRCh38' },
      },
    ])
    expect(steps[0].nextflow_path).toBe('nfcore/rnaseq/main.nf')
  })
})

describe('buildChainConnections', () => {
  it('extracts chain_connections from workflow artifact', () => {
    const conns = buildChainConnections({
      chain_connections: [
        { from_step: 1, from_output: 'filtered_smiles', to_step: 2, to_input: 'smiles' },
      ],
    })
    expect(conns).toHaveLength(1)
    expect(conns[0].to_input).toBe('smiles')
  })
})
