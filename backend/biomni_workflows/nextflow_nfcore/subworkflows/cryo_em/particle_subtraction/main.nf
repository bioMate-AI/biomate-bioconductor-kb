#!/usr/bin/env nextflow
/*
 * CryoSPARC Particle Subtraction
 *
 * Subtracts signal outside a mask from particle images, leaving only signal
 * from the region of interest (e.g., one domain of a multi-domain complex).
 * This enables focused classification and refinement on a single domain without
 * conformational heterogeneity from the rest of the assembly.
 *
 * Standard CryoSPARC job type: "particle_subtraction"
 *
 * References:
 *   Bharat & Scheres 2016 Nat Protoc 11:2054
 *   Nakane et al. 2018 eLife 7:e36861 (signal subtraction strategy)
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.subtraction_mask = 'auto'    // 'auto' or path to mask volume (.mrc)
params.invert_mask      = false     // if true, keep signal outside mask instead
params.use_cryosparc    = false     // use live CryoSPARC API
params.outdir           = './results/particle_subtraction'

// ============================================================================
// Process Definition
// ============================================================================

process PARTICLE_SUBTRACTION {
    tag "particle_subtraction"
    publishDir "${params.outdir}/particle_subtraction", mode: 'copy'

    input:
    path particles_cs
    path volume_cs

    output:
    path "subtracted_particles.cs",   emit: subtracted_particles_cs
    path "subtraction_report.json",   emit: report

    script:
    def invert_mask = params.invert_mask  ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    invert_mask = ${invert_mask}
    mask_param  = '${params.subtraction_mask}'

    particles_data = json.load(open('${particles_cs}'))
    volume_data    = json.load(open('${volume_cs}'))

    particles     = particles_data.get('particles', [])
    num_particles = len(particles)
    volume        = volume_data.get('volume', {})
    resolution_angstroms = volume.get('resolution_angstroms', 4.0)

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

        job_params = {'invert_mask': invert_mask}
        if mask_param != 'auto':
            job_params['mask'] = mask_param

        job = workspace.create_job('particle_subtract', connections={
            'particles': ('${params.cryosparc_particles_job_uid ?: ""}', 'particles'),
            'volume':    ('${params.cryosparc_volume_job_uid ?: ""}', 'volume')
        }, params=job_params)
        job.queue()
        job.wait_for_done()

        subtracted_out = list(job.load_output('particles'))
        cs_data = {
            'particles':      subtracted_out,
            'num_subtracted': len(subtracted_out),
            'mask_used':      mask_param
        }
        stats = job.doc.get('output_stats', {})
        signal_fraction_removed = stats.get('signal_fraction_removed', 0.0)
        mask_radius_angstroms   = stats.get('mask_radius_angstroms', 0.0)
        mask_volume_angstroms   = stats.get('mask_volume_angstroms_cubed', 0.0)
    else:
        raise RuntimeError(
            "CryoSPARC connection required. Set --use_cryosparc true and provide "
            "CryoSPARC connection params."
        )

    with open('subtracted_particles.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)

    report = {
        'step':                        'particle_subtraction',
        'timestamp':                   datetime.now().isoformat(),
        'num_particles':               num_particles,
        'signal_fraction_removed':     signal_fraction_removed,
        'mask_volume_angstroms_cubed': mask_volume_angstroms,
        'mask_radius_angstroms':       mask_radius_angstroms,
        'mask_used':                   mask_param,
        'invert_mask':                 invert_mask,
        'input_resolution_angstroms':  resolution_angstroms
    }

    with open('subtraction_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Particle subtraction complete")
    print(f"  Particles processed : {num_particles}")
    print(f"  Mask used           : {mask_param}")
    print(f"  Invert mask         : {invert_mask}")
    """

    stub:
    """
    touch subtracted_particles.cs subtraction_report.json
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    ch_particles = Channel.fromPath(
        params.particles_cs ?: 'particles.cs',
        checkIfExists: true
    )

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: true
    )

    PARTICLE_SUBTRACTION(ch_particles, ch_volume)

    PARTICLE_SUBTRACTION.out.report.view { report_file ->
        def report = new groovy.json.JsonSlurper().parse(report_file)
        """
        Particle Subtraction Summary:
          - Particles processed : ${report.num_particles}
          - Signal removed      : ${report.signal_fraction_removed * 100}%
          - Mask used           : ${report.mask_used}
          - Mask volume         : ${report.mask_volume_angstroms_cubed} A3
        """
    }
}
