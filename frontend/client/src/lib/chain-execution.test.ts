import { describe, expect, it } from 'vitest'
import {
  buildChainConnections,
  buildChainSubmitSteps,
  pickChainStepSource,
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

describe('buildChainSubmitSteps — string entries', () => {
  it('maps a bare display string to workflow_name (backend resolves the path)', () => {
    const steps = buildChainSubmitSteps(['Predict ADMET Properties (AI)', 'pbpk_simulation'])
    expect(steps[0].workflow_name).toBe('Predict ADMET Properties (AI)')
    expect(steps[0].nextflow_path).toBeNull()
    expect(steps[1].workflow_name).toBe('pbpk_simulation')
  })
})

describe('pickChainStepSource', () => {
  // Regression: a workflow_type:'pipeline' artifact carries structured objects in
  // pipeline_steps AND a display-only string[] in chain_steps. The submit path must
  // pick the structured objects, not the strings (which resolve to null paths and
  // make the backend return no chain_run_id).
  it('prefers structured pipeline_steps over a display string[] chain_steps', () => {
    const src = pickChainStepSource({
      chain_steps: ['Predict ADMET Properties (AI)', 'pbpk_simulation', 'virtual_patient_cohort'],
      pipeline_steps: [
        { workflow_name: 'Predict ADMET Properties (AI)', nextflow_path: 'pharmacology/predict_admet_properties/main.nf' },
        { workflow_name: 'pbpk_simulation', nextflow_path: 'drug_discovery/pbpk_pediatric/main.nf' },
      ],
    })
    expect(typeof src[0]).toBe('object')
    expect((src[0] as Record<string, unknown>).nextflow_path).toContain('predict_admet_properties')
  })

  it('uses chain_steps when they are objects (workflow_type:chain artifacts)', () => {
    const src = pickChainStepSource({
      chain_steps: [{ workflow_name: 'deseq2', nextflow_path: 'differentialabundance/main.nf' }],
    })
    expect((src[0] as Record<string, unknown>).workflow_name).toBe('deseq2')
  })

  it('falls back to a string[] when no structured source exists', () => {
    const src = pickChainStepSource({ chain_steps: ['deseq2', 'enrichgo'] })
    expect(src).toEqual(['deseq2', 'enrichgo'])
  })

  it('returns [] when there are no steps', () => {
    expect(pickChainStepSource({})).toEqual([])
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
