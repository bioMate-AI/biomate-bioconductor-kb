#!/usr/bin/env nextflow
/*
 * CryoSPARC Global CTF Refinement
 *
 * Estimates and corrects global higher-order wavefront aberrations from the
 * full particle set after a high-resolution refinement.  Unlike per-particle
 * local CTF refinement (which estimates per-particle defocus), this step fits:
 *   - Beam tilt (x and y)  — first-order coma from gun or condenser misalignment
 *   - Anisotropic magnification — distortion from projector lens asymmetry
 *   - Trefoil              — third-order coma (usually sub-dominant)
 *   - Spherical aberration — refinement of the Cs value
 *
 * Standard CryoSPARC job type: "ctf_refine_global"
 *
 * References:
 *   Zivanov et al. 2018 eLife 7:e42166 (RELION beam-tilt correction)
 *   Zivanov et al. 2020 IUCrJ 7:253 (higher-order aberrations)
 *   Punjani et al. 2017 Nat Methods 14:290 (CryoSPARC)
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.fit_tilt         = true    // estimate and correct beam tilt (x, y)
params.fit_anisomag     = true    // estimate and correct anisotropic magnification
params.fit_trefoil      = false   // estimate and correct trefoil (third-order coma)
params.fit_spherical    = false   // refine spherical aberration Cs
params.mock_mode        = true    // use mock mode for testing
params.use_cryosparc    = false   // use live CryoSPARC API
params.outdir           = './results/global_ctf_refinement'

// ============================================================================
// Process Definition
// ============================================================================

process GLOBAL_CTF_REFINEMENT {
    tag "global_ctf_refinement"
    publishDir "${params.outdir}/global_ctf_refinement", mode: 'copy'

    input:
    path particles_cs
    path volume_cs

    output:
    path "particles_global_ctf.cs",     emit: particles_global_ctf_cs
    path "global_ctf_report.json",      emit: report

    script:
    def mock          = params.mock_mode      ? 'True'  : 'False'
    def fit_tilt      = params.fit_tilt       ? 'True'  : 'False'
    def fit_anisomag  = params.fit_anisomag   ? 'True'  : 'False'
    def fit_trefoil   = params.fit_trefoil    ? 'True'  : 'False'
    def fit_spherical = params.fit_spherical  ? 'True'  : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    random.seed(None)

    mock_mode     = ${mock}
    fit_tilt      = ${fit_tilt}
    fit_anisomag  = ${fit_anisomag}
    fit_trefoil   = ${fit_trefoil}
    fit_spherical = ${fit_spherical}

    particles_data = json.load(open('${particles_cs}'))
    volume_data    = json.load(open('${volume_cs}'))

    particles            = particles_data.get('particles', [])
    num_particles        = len(particles)
    volume               = volume_data.get('volume', {})
    resolution_before    = volume.get('resolution_angstroms', 3.5)

    # ---------------------------------------------------------------
    # Simulate beam tilt estimation
    # Realistic beam tilt: 0-3 mrad; > 1 mrad is noticeable.
    # Values in x and y are independent.
    # ---------------------------------------------------------------
    beam_tilt_x_mrad = round(random.uniform(-2.5, 2.5), 4) if fit_tilt else 0.0
    beam_tilt_y_mrad = round(random.uniform(-2.5, 2.5), 4) if fit_tilt else 0.0
    beam_tilt_magnitude_mrad = round(
        (beam_tilt_x_mrad ** 2 + beam_tilt_y_mrad ** 2) ** 0.5, 4
    )

    # ---------------------------------------------------------------
    # Simulate anisotropic magnification correction
    # Typical correction < 0.5% difference in x vs y magnification.
    # ---------------------------------------------------------------
    anisomag_xx = round(1.0 + random.gauss(0.0, 0.002), 6) if fit_anisomag else 1.0
    anisomag_yy = round(1.0 + random.gauss(0.0, 0.002), 6) if fit_anisomag else 1.0
    anisomag_xy = round(random.gauss(0.0, 0.001), 6)        if fit_anisomag else 0.0
    anisomag_correction_applied = fit_anisomag

    # ---------------------------------------------------------------
    # Simulate trefoil correction (rarely needed; sub-dominant term)
    # ---------------------------------------------------------------
    trefoil_amplitude_mrad = round(random.uniform(0.0, 0.5), 4) if fit_trefoil else 0.0
    trefoil_angle_degrees  = round(random.uniform(0.0, 120.0), 2) if fit_trefoil else 0.0

    # ---------------------------------------------------------------
    # Simulate spherical aberration refinement
    # Nominal Cs = 2.7 mm; refined within ±0.1 mm
    # ---------------------------------------------------------------
    cs_original_mm  = 2.7
    cs_refined_mm   = round(cs_original_mm + random.gauss(0.0, 0.05), 4) if fit_spherical else cs_original_mm

    # ---------------------------------------------------------------
    # Resolution improvement from aberration correction.
    # Beam tilt correction typically gains 0.1-0.5 A at high resolution.
    # ---------------------------------------------------------------
    tilt_contrib      = abs(beam_tilt_magnitude_mrad) * random.uniform(0.05, 0.15) if fit_tilt else 0.0
    anisomag_contrib  = random.uniform(0.0, 0.08) if fit_anisomag else 0.0
    trefoil_contrib   = abs(trefoil_amplitude_mrad) * random.uniform(0.01, 0.05) if fit_trefoil else 0.0
    total_improvement = round(tilt_contrib + anisomag_contrib + trefoil_contrib, 3)

    resolution_after = round(
        max(1.5, resolution_before - total_improvement), 2
    )
    resolution_improvement = round(resolution_before - resolution_after, 3)

    # Annotate particles with global CTF correction applied
    corrected_particles = []
    for p in particles:
        entry = dict(p)
        entry['global_ctf_applied']          = True
        entry['beam_tilt_x_mrad_correction'] = beam_tilt_x_mrad
        entry['beam_tilt_y_mrad_correction'] = beam_tilt_y_mrad
        entry['anisomag_applied']             = anisomag_correction_applied
        corrected_particles.append(entry)

    cs_data = {
        'particles':          corrected_particles,
        'global_ctf_applied': True
    }

    report = {
        'step':                          'global_ctf_refinement',
        'timestamp':                     datetime.now().isoformat(),
        'num_particles':                 num_particles,

        # Beam tilt
        'fit_tilt':                      fit_tilt,
        'beam_tilt_x_mrad':              beam_tilt_x_mrad,
        'beam_tilt_y_mrad':              beam_tilt_y_mrad,
        'beam_tilt_magnitude_mrad':      beam_tilt_magnitude_mrad,

        # Anisotropic magnification
        'fit_anisomag':                  fit_anisomag,
        'anisomag_correction_applied':   anisomag_correction_applied,
        'anisomag_matrix': {
            'xx': anisomag_xx,
            'yy': anisomag_yy,
            'xy': anisomag_xy
        },

        # Trefoil
        'fit_trefoil':                   fit_trefoil,
        'trefoil_amplitude_mrad':        trefoil_amplitude_mrad,
        'trefoil_angle_degrees':         trefoil_angle_degrees,

        # Spherical aberration
        'fit_spherical':                 fit_spherical,
        'cs_original_mm':                cs_original_mm,
        'cs_refined_mm':                 cs_refined_mm,

        # Resolution impact
        'resolution_before_angstroms':   resolution_before,
        'resolution_after_angstroms':    resolution_after,
        'resolution_improvement_angstroms': resolution_improvement,

        'mock_mode':                     mock_mode
    }

    with open('particles_global_ctf.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)

    with open('global_ctf_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Global CTF refinement complete")
    print(f"  Particles    : {num_particles}")
    if fit_tilt:
        print(f"  Beam tilt    : x={beam_tilt_x_mrad:.3f} mrad, "
              f"y={beam_tilt_y_mrad:.3f} mrad  "
              f"(|tilt| = {beam_tilt_magnitude_mrad:.3f} mrad)")
    if fit_anisomag:
        print(f"  Anisomag     : applied  (Mxx={anisomag_xx:.5f}, Myy={anisomag_yy:.5f})")
    if fit_trefoil:
        print(f"  Trefoil      : {trefoil_amplitude_mrad:.3f} mrad @ {trefoil_angle_degrees:.1f} deg")
    if fit_spherical:
        print(f"  Cs refined   : {cs_original_mm} mm -> {cs_refined_mm} mm")
    print(f"  Resolution   : {resolution_before:.2f} A -> {resolution_after:.2f} A  "
          f"(+{resolution_improvement:.3f} A)")
    """

    stub:
    """
    touch particles_global_ctf.cs global_ctf_report.json
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    log.info """
    ====================================================================
    CryoSPARC Global CTF Refinement
    ====================================================================
    Fit beam tilt         : ${params.fit_tilt}
    Fit anisomag          : ${params.fit_anisomag}
    Fit trefoil           : ${params.fit_trefoil}
    Fit spherical (Cs)    : ${params.fit_spherical}
    Mode                  : ${params.mock_mode ? 'MOCK (testing)' : 'LIVE (CryoSPARC)'}
    ====================================================================
    """.stripIndent()

    ch_particles = Channel.fromPath(
        params.particles_cs ?: 'particles.cs',
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/particles.cs")
        f.parent.mkdirs()
        f.text = '{"particles": [' +
            (1..500).collect { i ->
                """{"particle_idx": ${i}, "micrograph_idx": ${i % 100}, """ +
                """"x_coord": 2000, "y_coord": 2000, "pick_score": 0.95, """ +
                """"ctf_refined": true, "local_defocus_shift": ${(int)(Math.random() * 1000 - 500)}}"""
            }.join(',') + ']}'
        f
    }

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/volume.cs")
        f.parent.mkdirs()
        f.text = '{"volume": {"resolution_angstroms": 3.2, "symmetry": "C1", "num_particles": 500}}'
        f
    }

    GLOBAL_CTF_REFINEMENT(ch_particles, ch_volume)

    GLOBAL_CTF_REFINEMENT.out.report.view { report_file ->
        def report = new groovy.json.JsonSlurper().parse(report_file)
        """
        Global CTF Refinement Summary:
          - Particles           : ${report.num_particles}
          - Beam tilt (x, y)    : ${report.beam_tilt_x_mrad} / ${report.beam_tilt_y_mrad} mrad
          - Anisomag applied    : ${report.anisomag_correction_applied}
          - Resolution before   : ${report.resolution_before_angstroms} A
          - Resolution after    : ${report.resolution_after_angstroms} A
          - Improvement         : +${report.resolution_improvement_angstroms} A
        """
    }
}
