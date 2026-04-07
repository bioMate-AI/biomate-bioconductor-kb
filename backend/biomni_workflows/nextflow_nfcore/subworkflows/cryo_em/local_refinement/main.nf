#!/usr/bin/env nextflow
/*
 * CryoSPARC Local / Focused Refinement
 *
 * Focused refinement of signal-subtracted particle images. Particle alignments
 * are constrained to a region defined by a focus mask, enabling high-resolution
 * analysis of one domain of a complex by removing contributions from the rest
 * of the assembly.  Typically follows particle subtraction.
 *
 * Standard CryoSPARC job type: "local_refine"
 *
 * References:
 *   Nakane et al. 2018 eLife 7:e36861
 *   Zivanov et al. 2019 IUCrJ 6:531 (focused refinement theory)
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.focus_mask       = null      // path to focus mask .mrc; null = auto tight mask
params.symmetry         = 'C1'      // point group symmetry for the focused region
params.initial_lowpass  = 8.0       // Angstroms — initial lowpass filter for alignment
params.max_iterations   = 20        // maximum refinement iterations
params.use_cryosparc    = false     // use live CryoSPARC API
params.outdir           = './results/local_refinement'

// ============================================================================
// Process Definition
// ============================================================================

process LOCAL_REFINEMENT {
    tag "local_refinement"
    label 'process_gpu'
    publishDir "${params.outdir}/local_refinement", mode: 'copy'

    input:
    path subtracted_particles_cs
    path volume_cs

    output:
    path "local_refined_volume.cs",       emit: refined_volume_cs
    path "local_refinement_report.json",  emit: report

    script:
    def focus_mask = params.focus_mask  ? "'${params.focus_mask}'" : 'None'
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    symmetry        = '${params.symmetry}'
    initial_lowpass = ${params.initial_lowpass}
    max_iterations  = ${params.max_iterations}
    focus_mask      = ${focus_mask}

    particles_data = json.load(open('${subtracted_particles_cs}'))
    volume_data    = json.load(open('${volume_cs}'))

    particles     = particles_data.get('particles', [])
    num_particles = len(particles)
    volume        = volume_data.get('volume', {})

    initial_res = volume.get('resolution_angstroms',
                  particles_data.get('input_resolution_angstroms', 5.5))

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

        job_params = {
            'symmetry':       symmetry,
            'init_res':       initial_lowpass,
            'max_iterations': max_iterations
        }
        if focus_mask is not None:
            job_params['mask'] = focus_mask

        job = workspace.create_job('local_refine', connections={
            'particles': ('${params.cryosparc_particles_job_uid ?: ""}', 'particles'),
            'volume':    ('${params.cryosparc_volume_job_uid ?: ""}', 'volume')
        }, params=job_params)
        job.queue()
        job.wait_for_done()

        stats = job.doc.get('output_stats', {})
        final_res   = stats.get('fsc_resolution_0143', initial_res)
        local_res   = stats.get('local_resolution', final_res)
        improvement_pct = round((initial_res - final_res) / initial_res * 100.0, 2) if initial_res > 0 else 0.0

        refined = {
            'resolution_angstroms':       final_res,
            'local_resolution_angstroms': local_res,
            'symmetry':                   symmetry,
            'focus_mask':                 focus_mask,
            'num_particles':              num_particles,
            'initial_resolution_angstroms': initial_res
        }
        with open('local_refined_volume.cs', 'w') as f:
            json.dump({'volume': refined}, f, indent=2)
    else:
        raise RuntimeError(
            "CryoSPARC connection required. Set --use_cryosparc true and provide "
            "CryoSPARC connection params."
        )

    report = {
        'step':                          'local_refinement',
        'timestamp':                     datetime.now().isoformat(),
        'num_particles':                 num_particles,
        'initial_resolution_angstroms':  initial_res,
        'final_resolution_angstroms':    final_res,
        'resolution_improvement_pct':    improvement_pct,
        'local_fsc_0143_resolution':     final_res,
        'local_resolution_angstroms':    local_res,
        'symmetry':                      symmetry,
        'focus_mask':                    focus_mask,
        'initial_lowpass_angstroms':     initial_lowpass,
        'max_iterations':                max_iterations
    }

    with open('local_refinement_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Local refinement complete")
    print(f"  Particles      : {num_particles}")
    print(f"  Resolution     : {initial_res:.2f} A -> {final_res:.2f} A  "
          f"({improvement_pct:.1f}% improvement)")
    print(f"  Local FSC 0.143: {final_res:.2f} A")
    print(f"  Symmetry       : {symmetry}")
    """

    stub:
    """
    touch local_refined_volume.cs local_refinement_report.json
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    ch_particles = Channel.fromPath(
        params.subtracted_particles_cs ?: 'subtracted_particles.cs',
        checkIfExists: true
    )

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: true
    )

    LOCAL_REFINEMENT(ch_particles, ch_volume)

    LOCAL_REFINEMENT.out.report.view { report_file ->
        def report = new groovy.json.JsonSlurper().parse(report_file)
        """
        Local Refinement Summary:
          - Particles          : ${report.num_particles}
          - Initial resolution : ${report.initial_resolution_angstroms} A
          - Final resolution   : ${report.final_resolution_angstroms} A
          - Improvement        : ${report.resolution_improvement_pct}%
          - Local FSC 0.143    : ${report.local_fsc_0143_resolution} A
        """
    }
}
