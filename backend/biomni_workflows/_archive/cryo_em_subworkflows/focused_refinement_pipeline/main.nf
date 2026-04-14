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
params.mock_mode        = true      // use mock mode for testing
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
    def mock        = params.mock_mode   ? 'True' : 'False'
    def invert_mask = params.invert_mask ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import math
    import random
    from datetime import datetime

    random.seed(None)

    mock_mode   = ${mock}
    invert_mask = ${invert_mask}
    mask_param  = '${params.subtraction_mask}'

    particles_data = json.load(open('${particles_cs}'))
    volume_data    = json.load(open('${volume_cs}'))

    particles    = particles_data.get('particles', [])
    num_particles = len(particles)

    volume = volume_data.get('volume', {})
    resolution_angstroms = volume.get('resolution_angstroms', 4.0)

    if mask_param == 'auto':
        mask_used = 'auto_spherical_mask'
        mask_radius_angstroms = round(random.uniform(35.0, 65.0), 1)
    else:
        mask_used = mask_param
        mask_radius_angstroms = round(random.uniform(30.0, 70.0), 1)

    signal_fraction_removed = round(random.uniform(0.35, 0.65), 4)
    mask_volume_angstroms = round(
        (4.0 / 3.0) * math.pi * (mask_radius_angstroms ** 3), 1
    )

    subtracted = []
    for p in particles:
        entry = dict(p)
        entry['subtracted']              = True
        entry['signal_fraction_removed'] = signal_fraction_removed
        entry['mask_used']               = mask_used
        entry['invert_mask']             = invert_mask
        subtracted.append(entry)

    cs_data = {
        'particles':      subtracted,
        'num_subtracted': len(subtracted),
        'mask_used':      mask_used
    }

    report = {
        'step':                        'particle_subtraction',
        'timestamp':                   datetime.now().isoformat(),
        'num_particles':               num_particles,
        'signal_fraction_removed':     signal_fraction_removed,
        'mask_volume_angstroms_cubed': mask_volume_angstroms,
        'mask_radius_angstroms':       mask_radius_angstroms,
        'mask_used':                   mask_used,
        'invert_mask':                 invert_mask,
        'input_resolution_angstroms':  resolution_angstroms,
        'mock_mode':                   mock_mode
    }

    with open('subtracted_particles.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)

    with open('subtraction_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"[1/3] Particle subtraction complete")
    print(f"  Particles : {num_particles}  |  Signal removed: {signal_fraction_removed * 100:.1f}%")
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
    def mock       = params.mock_mode  ? 'True' : 'False'
    def focus_mask = params.focus_mask ? "'${params.focus_mask}'" : 'None'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    random.seed(None)

    mock_mode       = ${mock}
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

    improvement_pct = round(random.uniform(15.0, 35.0), 2)
    final_res       = round(initial_res * (1.0 - improvement_pct / 100.0), 2)
    final_res       = max(2.0, min(10.0, final_res))
    local_res       = round(final_res * random.uniform(0.85, 0.98), 2)
    local_fsc_0143  = final_res

    refined = {
        'resolution_angstroms':         final_res,
        'local_resolution_angstroms':   local_res,
        'symmetry':                     symmetry,
        'focus_mask':                   focus_mask,
        'num_particles':                num_particles,
        'initial_resolution_angstroms': initial_res
    }

    report = {
        'step':                         'local_refinement',
        'timestamp':                    datetime.now().isoformat(),
        'num_particles':                num_particles,
        'initial_resolution_angstroms': initial_res,
        'final_resolution_angstroms':   final_res,
        'resolution_improvement_pct':   improvement_pct,
        'local_fsc_0143_resolution':    local_fsc_0143,
        'local_resolution_angstroms':   local_res,
        'symmetry':                     symmetry,
        'focus_mask':                   focus_mask,
        'initial_lowpass_angstroms':    initial_lowpass,
        'max_iterations':               max_iterations,
        'mock_mode':                    mock_mode
    }

    with open('local_refined_volume.cs', 'w') as f:
        json.dump({'volume': refined}, f, indent=2)

    with open('local_refinement_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"[2/3] Local refinement complete")
    print(f"  Resolution : {initial_res:.2f} A -> {final_res:.2f} A  "
          f"({improvement_pct:.1f}% improvement)")
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
    def mock = params.mock_mode ? 'True' : 'False'
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
        'mock_mode':                       ${mock},

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
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/particles.cs")
        f.parent.mkdirs()
        f.text = '{"particles": [' +
            (1..200).collect { i ->
                """{"particle_idx": ${i}, "micrograph_idx": ${i % 50}, """ +
                """"x_coord": ${(int)(Math.random() * 3800) + 100}, """ +
                """"y_coord": ${(int)(Math.random() * 3800) + 100}, """ +
                """"pick_score": 0.85, "pick_method": "template"}"""
            }.join(',') + ']}'
        f
    }

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/volume.cs")
        f.parent.mkdirs()
        f.text = '{"volume": {"resolution_angstroms": 4.5, "symmetry": "C1", "num_particles": 200}}'
        f
    }

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
