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
params.mock_mode        = true      // use mock mode for testing
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
    def mock        = params.mock_mode    ? 'True' : 'False'
    def invert_mask = params.invert_mask  ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    random.seed(None)

    mock_mode   = ${mock}
    invert_mask = ${invert_mask}
    mask_param  = '${params.subtraction_mask}'

    particles_data = json.load(open('${particles_cs}'))
    volume_data    = json.load(open('${volume_cs}'))

    particles = particles_data.get('particles', [])
    num_particles = len(particles)

    # Simulate volume dimensions from the input volume
    volume = volume_data.get('volume', {})
    resolution_angstroms = volume.get('resolution_angstroms', 4.0)

    # Determine mask: auto-generate a spherical mask or use provided path
    if mask_param == 'auto':
        mask_used = 'auto_spherical_mask'
        # Spherical mask radius is ~60-80% of particle box
        mask_radius_angstroms = round(random.uniform(35.0, 65.0), 1)
    else:
        mask_used = mask_param
        mask_radius_angstroms = round(random.uniform(30.0, 70.0), 1)

    # Signal fraction removed: realistic range 35-65% depending on domain size
    signal_fraction_removed = round(random.uniform(0.35, 0.65), 4)

    # Simulated mask volume in cubic Angstroms
    import math
    mask_volume_angstroms = round(
        (4.0 / 3.0) * math.pi * (mask_radius_angstroms ** 3), 1
    )

    # Add subtraction metadata to each particle
    subtracted = []
    for p in particles:
        entry = dict(p)
        entry['subtracted']             = True
        entry['signal_fraction_removed'] = signal_fraction_removed
        entry['mask_used']              = mask_used
        entry['invert_mask']            = invert_mask
        subtracted.append(entry)

    cs_data = {
        'particles':    subtracted,
        'num_subtracted': len(subtracted),
        'mask_used':    mask_used
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

    print(f"Particle subtraction complete")
    print(f"  Particles processed : {num_particles}")
    print(f"  Signal removed      : {signal_fraction_removed * 100:.1f}%")
    print(f"  Mask used           : {mask_used}")
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
    // Create dummy input channels for standalone testing
    ch_particles = Channel.fromPath(
        params.particles_cs ?: 'particles.cs',
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/particles.cs")
        f.parent.mkdirs()
        f.text = '{"particles": [{"particle_idx": 0, "micrograph_idx": 0, "x_coord": 1000, "y_coord": 1000, "pick_score": 0.95, "pick_method": "template"}]}'
        f
    }

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/volume.cs")
        f.parent.mkdirs()
        f.text = '{"volume": {"resolution_angstroms": 3.8, "symmetry": "C1", "num_particles": 1}}'
        f
    }

    PARTICLE_SUBTRACTION(ch_particles, ch_volume)

    PARTICLE_SUBTRACTION.out.report.view { report_file ->
        def report = new groovy.json.JsonSlurper().parse(report_file)
        """
        Particle Subtraction Summary:
          - Particles processed : ${report.num_particles}
          - Signal removed      : ${report.signal_fraction_removed * 100}%
          - Mask used           : ${report.mask_used}
          - Mask volume         : ${report.mask_volume_angstroms_cubed} Å³
        """
    }
}
