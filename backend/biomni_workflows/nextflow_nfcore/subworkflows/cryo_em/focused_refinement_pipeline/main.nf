#!/usr/bin/env nextflow
/*
 * CryoSPARC Focused Refinement Pipeline
 *
 * Orchestrates the two-step focused/local refinement workflow:
 *   1. Particle Subtraction — removes signal outside the region of interest
 *   2. Local Refinement     — aligns subtracted particles to the focused domain
 *   3. Focused Refinement Summary — aggregates metrics from both steps
 *
 * Typical use case: a multi-domain complex where one flexible arm prevents
 * high-resolution reconstruction of the stable core, or vice versa.
 *
 * References:
 *   Nakane et al. 2018 eLife 7:e36861
 *   Bharat & Scheres 2016 Nat Protoc 11:2054
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters — merged from both sub-modules
// ============================================================================

// --- Particle Subtraction ---
params.subtraction_mask = 'auto'    // 'auto' or path to mask volume (.mrc)
params.invert_mask      = false     // if true, keep signal outside mask instead

// --- Local Refinement ---
params.focus_mask       = null      // path to focus mask .mrc; null = auto tight mask
params.symmetry         = 'C1'      // point group symmetry for the focused region
params.initial_lowpass  = 8.0       // Angstroms — initial lowpass for alignment
params.max_iterations   = 20        // maximum refinement iterations

// --- Global ---
params.use_cryosparc    = false     // use live CryoSPARC API
params.outdir           = './results/focused_refinement'

// ============================================================================
// Process Definitions (inline)
// ============================================================================

process PARTICLE_SUBTRACTION {
    tag "particle_subtraction"
    publishDir "${params.outdir}/01_particle_subtraction", mode: 'copy'

    input:
    path particles_cs
    path volume_cs

    output:
    path "subtracted_particles.cs",  emit: subtracted_particles_cs
    path "subtraction_report.json",  emit: report

    script:
    def invert_mask = params.invert_mask ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    invert_mask = ${invert_mask}
    mask_param  = '${params.subtraction_mask}'

    particles_data = json.load(open('${particles_cs}'))
    volume_data    = json.load(open('${volume_cs}'))

    particles    = particles_data.get('particles', [])
    num_particles = len(particles)
    volume = volume_data.get('volume', {})
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
        signal_fraction_removed = job.doc.get('output_stats', {}).get('signal_fraction_removed', 0.0)
        mask_radius_angstroms   = job.doc.get('output_stats', {}).get('mask_radius_angstroms', 0.0)
        mask_volume_angstroms   = 0.0
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

    print(f"[1/3] Particle subtraction complete")
    print(f"  Particles : {num_particles}")
    """

    stub:
    """
    touch subtracted_particles.cs subtraction_report.json
    """
}

process LOCAL_REFINEMENT {
    tag "local_refinement"
    label 'process_gpu'
    publishDir "${params.outdir}/02_local_refinement", mode: 'copy'

    input:
    path subtracted_particles_cs
    path volume_cs

    output:
    path "local_refined_volume.cs",      emit: refined_volume_cs
    path "local_refinement_report.json", emit: report

    script:
    def focus_mask = params.focus_mask ? "'${params.focus_mask}'" : 'None'
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
    initial_res   = volume.get('resolution_angstroms',
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
            'symmetry':           symmetry,
            'init_res':           initial_lowpass,
            'max_iterations':     max_iterations
        }
        if focus_mask is not None:
            job_params['mask'] = focus_mask

        job = workspace.create_job('local_refine', connections={
            'particles': ('${params.cryosparc_subtracted_job_uid ?: ""}', 'particles'),
            'volume':    ('${params.cryosparc_volume_job_uid ?: ""}', 'volume')
        }, params=job_params)
        job.queue()
        job.wait_for_done()

        vol_out = job.doc.get('output_stats', {})
        final_res = vol_out.get('fsc_resolution_0143', initial_res)
        local_res = vol_out.get('local_resolution', final_res)
        improvement_pct = round((initial_res - final_res) / initial_res * 100.0, 2) if initial_res > 0 else 0.0

        refined = {
            'resolution_angstroms':         final_res,
            'local_resolution_angstroms':   local_res,
            'symmetry':                     symmetry,
            'focus_mask':                   focus_mask,
            'num_particles':                num_particles,
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
        'step':                         'local_refinement',
        'timestamp':                    datetime.now().isoformat(),
        'num_particles':                num_particles,
        'initial_resolution_angstroms': initial_res,
        'final_resolution_angstroms':   final_res,
        'resolution_improvement_pct':   improvement_pct,
        'local_fsc_0143_resolution':    final_res,
        'local_resolution_angstroms':   local_res,
        'symmetry':                     symmetry,
        'focus_mask':                   focus_mask,
        'initial_lowpass_angstroms':    initial_lowpass,
        'max_iterations':               max_iterations
    }

    with open('local_refinement_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"[2/3] Local refinement complete")
    print(f"  Resolution : {initial_res:.2f} A -> {final_res:.2f} A")
    """

    stub:
    """
    touch local_refined_volume.cs local_refinement_report.json
    """
}

process FOCUSED_REFINEMENT_SUMMARY {
    tag "focused_refinement_summary"
    publishDir "${params.outdir}/03_summary", mode: 'copy'

    input:
    path subtraction_report
    path local_refinement_report
    path refined_volume_cs

    output:
    path "focused_refinement_summary.json", emit: summary

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    sub_report  = json.load(open('${subtraction_report}'))
    ref_report  = json.load(open('${local_refinement_report}'))
    volume_data = json.load(open('${refined_volume_cs}'))

    volume = volume_data.get('volume', {})

    summary = {
        'workflow':                        'focused_refinement_pipeline',
        'version':                         '1.0',
        'completion_time':                 datetime.now().isoformat(),
        'steps_completed':                 2,

        # Subtraction metrics
        'num_particles':                   sub_report['num_particles'],
        'signal_fraction_removed':         sub_report['signal_fraction_removed'],
        'mask_used':                       sub_report['mask_used'],
        'mask_radius_angstroms':           sub_report['mask_radius_angstroms'],

        # Refinement metrics
        'initial_resolution_angstroms':    ref_report['initial_resolution_angstroms'],
        'final_resolution_angstroms':      ref_report['final_resolution_angstroms'],
        'resolution_improvement_pct':      ref_report['resolution_improvement_pct'],
        'local_fsc_0143_resolution':       ref_report['local_fsc_0143_resolution'],
        'local_resolution_angstroms':      ref_report['local_resolution_angstroms'],
        'symmetry':                        ref_report['symmetry'],

        'outputs': {
            'refined_volume':              'local_refined_volume.cs',
            'subtraction_report':          'subtraction_report.json',
            'refinement_report':           'local_refinement_report.json'
        }
    }

    with open('focused_refinement_summary.json', 'w') as f:
        json.dump(summary, f, indent=2)

    print("")
    print("=" * 70)
    print("  Focused Refinement Pipeline Complete!")
    print("=" * 70)
    print(f"  Particles processed     : {summary['num_particles']}")
    print(f"  Signal removed          : {summary['signal_fraction_removed'] * 100:.1f}%")
    print(f"  Initial resolution      : {summary['initial_resolution_angstroms']:.2f} A")
    print(f"  Final resolution        : {summary['final_resolution_angstroms']:.2f} A")
    print(f"  Improvement             : {summary['resolution_improvement_pct']:.1f}%")
    print(f"  Local FSC 0.143         : {summary['local_fsc_0143_resolution']:.2f} A")
    print("=" * 70)
    """

    stub:
    """
    touch focused_refinement_summary.json
    """
}

// ============================================================================
// Named Workflow
// ============================================================================

workflow FOCUSED_REFINEMENT_PIPELINE {
    take:
    particles_cs
    volume_cs

    main:
    // Step 1: Particle Subtraction
    PARTICLE_SUBTRACTION(particles_cs, volume_cs)

    // Step 2: Local Refinement on subtracted particles
    LOCAL_REFINEMENT(
        PARTICLE_SUBTRACTION.out.subtracted_particles_cs,
        volume_cs
    )

    // Step 3: Summary
    FOCUSED_REFINEMENT_SUMMARY(
        PARTICLE_SUBTRACTION.out.report,
        LOCAL_REFINEMENT.out.report,
        LOCAL_REFINEMENT.out.refined_volume_cs
    )

    emit:
    refined_volume_cs = LOCAL_REFINEMENT.out.refined_volume_cs
    summary           = FOCUSED_REFINEMENT_SUMMARY.out.summary
}

// ============================================================================
// Standalone Execution
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

    FOCUSED_REFINEMENT_PIPELINE(ch_particles, ch_volume)

    FOCUSED_REFINEMENT_PIPELINE.out.summary.view { summary_file ->
        def summary = new groovy.json.JsonSlurper().parse(summary_file)
        """
        Focused Refinement Pipeline Summary:
          - Steps completed       : ${summary.steps_completed}/2
          - Final resolution      : ${summary.final_resolution_angstroms} A
          - Resolution improvement: ${summary.resolution_improvement_pct}%
          - Output volume         : ${summary.outputs.refined_volume}
        """
    }
}
