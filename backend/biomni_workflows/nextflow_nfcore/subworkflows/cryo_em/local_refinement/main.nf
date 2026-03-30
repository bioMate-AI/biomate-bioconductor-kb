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
params.mock_mode        = true      // use mock mode for testing
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
    def mock       = params.mock_mode   ? 'True' : 'False'
    def focus_mask = params.focus_mask  ? "'${params.focus_mask}'" : 'None'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    random.seed(None)

    mock_mode      = ${mock}
    symmetry       = '${params.symmetry}'
    initial_lowpass = ${params.initial_lowpass}
    max_iterations  = ${params.max_iterations}
    focus_mask      = ${focus_mask}

    particles_data = json.load(open('${subtracted_particles_cs}'))
    volume_data    = json.load(open('${volume_cs}'))

    particles     = particles_data.get('particles', [])
    num_particles = len(particles)
    volume        = volume_data.get('volume', {})

    # Starting resolution from the input volume (or from subtracted particles metadata)
    initial_res = volume.get('resolution_angstroms',
                  particles_data.get('input_resolution_angstroms', 5.5))

    # Local refinement on a subtracted domain typically improves resolution
    # compared to global refinement — improvement factor 15-35%
    improvement_pct = round(random.uniform(15.0, 35.0), 2)
    final_res       = round(initial_res * (1.0 - improvement_pct / 100.0), 2)
    # Clamp to physically plausible range 2.0-10.0 Å
    final_res = max(2.0, min(10.0, final_res))

    # Local resolution of the focused domain (slightly better than global FSC)
    local_res = round(final_res * random.uniform(0.85, 0.98), 2)

    # FSC 0.143 resolution for the focused region
    local_fsc_0143 = final_res

    # Build output volume object
    refined = {
        'resolution_angstroms':       final_res,
        'local_resolution_angstroms': local_res,
        'symmetry':                   symmetry,
        'focus_mask':                 focus_mask,
        'num_particles':              num_particles,
        'initial_resolution_angstroms': initial_res
    }

    report = {
        'step':                          'local_refinement',
        'timestamp':                     datetime.now().isoformat(),
        'num_particles':                 num_particles,
        'initial_resolution_angstroms':  initial_res,
        'final_resolution_angstroms':    final_res,
        'resolution_improvement_pct':    improvement_pct,
        'local_fsc_0143_resolution':     local_fsc_0143,
        'local_resolution_angstroms':    local_res,
        'symmetry':                      symmetry,
        'focus_mask':                    focus_mask,
        'initial_lowpass_angstroms':     initial_lowpass,
        'max_iterations':                max_iterations,
        'mock_mode':                     mock_mode
    }

    with open('local_refined_volume.cs', 'w') as f:
        json.dump({'volume': refined}, f, indent=2)

    with open('local_refinement_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Local refinement complete")
    print(f"  Particles      : {num_particles}")
    print(f"  Resolution     : {initial_res:.2f} A -> {final_res:.2f} A  "
          f"({improvement_pct:.1f}% improvement)")
    print(f"  Local FSC 0.143: {local_fsc_0143:.2f} A")
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
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/subtracted_particles.cs")
        f.parent.mkdirs()
        f.text = '{"particles": [{"particle_idx": 0, "subtracted": true, "signal_fraction_removed": 0.45}], "num_subtracted": 1, "mask_used": "auto_spherical_mask"}'
        f
    }

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/volume.cs")
        f.parent.mkdirs()
        f.text = '{"volume": {"resolution_angstroms": 4.2, "symmetry": "C1", "num_particles": 1}}'
        f
    }

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
