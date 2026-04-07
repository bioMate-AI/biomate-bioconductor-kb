#!/usr/bin/env nextflow
/*
 * CryoSPARC Helical Refinement
 *
 * Gold-standard helical reconstruction from filament particles.  Applies
 * helical symmetry (rise + twist) during reconstruction, producing a helical
 * tube map with atomic-resolution detail when data quality permits.
 * Corresponds to the CryoSPARC "helical_refine" job type.
 *
 * Typical helical parameters (rise Å / twist °):
 *   F-actin              : 27.5 / -166.15
 *   alpha-synuclein amyloid : 4.75 / -179.35  (Gremer 2017 Science)
 *   tau paired helical   : 2.37 / 179.46      (Fitzpatrick 2017 Nature)
 *   TMV virus rod        : 1.41 / 22.03
 *   Microtubule 13-pf    : 8.17 / 0.30        (Alushin 2014 Cell)
 *
 * References:
 *   He & Bharat 2021 eLife 10:e71636  (CryoSPARC helical refinement)
 *   Egelman 2007 Structure 15:1267    (iterative helical real-space reconstruction)
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.helical_rise_angstroms  = 4.75      // Å  inter-subunit axial rise
params.helical_twist_deg       = -166.15   // °  inter-subunit rotation (actin default)
params.symmetry                = 'C1'      // point-group symmetry atop helical symmetry
params.initial_lowpass         = 12.0      // Å  low-pass filter for initial reference
params.refine_helical_params   = true      // allow CryoSPARC to refine rise and twist
params.use_cryosparc           = false
params.outdir                  = './results/helical_refinement'

// ============================================================================
// Process Definition
// ============================================================================

process HELICAL_REFINEMENT {
    tag "helical_refinement"
    label 'process_gpu'
    publishDir "${params.outdir}/helical_refinement", mode: 'copy'

    input:
    path particles_cs
    path volume_cs

    output:
    path "helical_volume.cs",               emit: helical_volume_cs
    path "helical_refinement_report.json",  emit: report

    script:
    def refine_params = params.refine_helical_params ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    refine_hel      = ${refine_params}

    particles_data  = json.load(open('${particles_cs}'))
    volume_data     = json.load(open('${volume_cs}'))

    particles       = particles_data.get('particles', particles_data.get('picks', []))
    num_particles   = len(particles)

    input_rise      = ${params.helical_rise_angstroms}
    input_twist     = ${params.helical_twist_deg}
    symmetry        = '${params.symmetry}'
    initial_lowpass = ${params.initial_lowpass}

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('helical_refine', connections={
            'particles': ('${params.cryosparc_particles_job_uid ?: ""}', 'particles'),
            'volume':    ('${params.cryosparc_volume_job_uid ?: ""}', 'volume')
        }, params={
            'helical_rise_A':       input_rise,
            'helical_twist_deg':    input_twist,
            'symmetry':             symmetry,
            'init_res':             initial_lowpass,
            'refine_helical':       refine_hel
        })
        job.queue()
        job.wait_for_done()

        stats = job.doc.get('output_stats', {})
        refined_rise  = stats.get('helical_rise_A', input_rise)
        refined_twist = stats.get('helical_twist_deg', input_twist)
        final_res     = stats.get('fsc_resolution_0143', 0.0)

        volume_out = {
            'volume': {
                'resolution_angstroms': final_res,
                'helical_rise':         refined_rise,
                'helical_twist':        refined_twist,
                'symmetry':             symmetry,
                'volume_path':          'helical_volume.mrc'
            }
        }
        with open('helical_volume.cs', 'w') as f:
            json.dump(volume_out, f, indent=2)
    else:
        raise RuntimeError(
            "CryoSPARC connection required. Set --use_cryosparc true and provide "
            "CryoSPARC connection params."
        )

    report = {
        'step':                              'helical_refinement',
        'timestamp':                         datetime.now().isoformat(),
        'input_helical_rise_angstroms':      input_rise,
        'input_helical_twist_deg':           input_twist,
        'refined_helical_rise_angstroms':    refined_rise,
        'refined_helical_twist_deg':         refined_twist,
        'final_fsc_0143_resolution':         final_res,
        'helical_rise_convergence_angstroms': round(abs(refined_rise - input_rise), 4),
        'helical_twist_convergence_deg':     round(abs(refined_twist - input_twist), 4),
        'num_particles':                     num_particles,
        'symmetry':                          symmetry,
        'initial_lowpass_angstroms':         initial_lowpass,
        'refine_helical_params':             refine_hel
    }

    with open('helical_refinement_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Helical refinement complete")
    print(f"  Particles used              : {num_particles}")
    print(f"  Final resolution (FSC=0.143): {final_res} A")
    print(f"  Refined rise                : {refined_rise} A  (input: {input_rise} A)")
    print(f"  Refined twist               : {refined_twist} deg  (input: {input_twist} deg)")
    """
}

// ============================================================================
// Workflow (standalone execution)
// ============================================================================

workflow {
    log.info """
    ====================================================================
    CryoSPARC Helical Refinement
    ====================================================================
    Helical rise  : ${params.helical_rise_angstroms} A
    Helical twist : ${params.helical_twist_deg} deg
    Symmetry      : ${params.symmetry}
    Initial lowpass: ${params.initial_lowpass} A
    Refine params : ${params.refine_helical_params}
    Output        : ${params.outdir}
    ====================================================================
    """.stripIndent()

    ch_particles = Channel.fromPath(
        params.particles_cs ?: 'particles.cs',
        checkIfExists: true
    )

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: true
    )

    HELICAL_REFINEMENT(ch_particles, ch_volume)

    HELICAL_REFINEMENT.out.report.view { report_file ->
        def r = new groovy.json.JsonSlurper().parse(report_file)
        """
        Helical Refinement Results:
          Particles         : ${r.num_particles}
          Final resolution  : ${r.final_fsc_0143_resolution} A
          Refined rise      : ${r.refined_helical_rise_angstroms} A
          Refined twist     : ${r.refined_helical_twist_deg} deg
        Results in: ${params.outdir}
        """
    }
}

workflow.onComplete {
    log.info "Helical Refinement completed: ${workflow.success ? 'SUCCESS' : 'FAILED'} (${workflow.duration})"
}
