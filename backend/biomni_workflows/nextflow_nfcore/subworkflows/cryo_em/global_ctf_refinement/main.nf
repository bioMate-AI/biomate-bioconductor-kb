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
    def fit_tilt      = params.fit_tilt       ? 'True'  : 'False'
    def fit_anisomag  = params.fit_anisomag   ? 'True'  : 'False'
    def fit_trefoil   = params.fit_trefoil    ? 'True'  : 'False'
    def fit_spherical = params.fit_spherical  ? 'True'  : 'False'
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    fit_tilt      = ${fit_tilt}
    fit_anisomag  = ${fit_anisomag}
    fit_trefoil   = ${fit_trefoil}
    fit_spherical = ${fit_spherical}

    particles_data = json.load(open('${particles_cs}'))
    volume_data    = json.load(open('${volume_cs}'))

    particles         = particles_data.get('particles', [])
    num_particles     = len(particles)
    volume            = volume_data.get('volume', {})
    resolution_before = volume.get('resolution_angstroms', 3.5)

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

        job = workspace.create_job('ctf_refine_global', connections={
            'particles': ('${params.cryosparc_particles_job_uid ?: ""}', 'particles'),
            'volume':    ('${params.cryosparc_volume_job_uid ?: ""}', 'volume')
        }, params={
            'ctf_refine_fit_tilt':        fit_tilt,
            'ctf_refine_fit_anisomag':    fit_anisomag,
            'ctf_refine_fit_trefoil':     fit_trefoil,
            'ctf_refine_fit_spherical':   fit_spherical
        })
        job.queue()
        job.wait_for_done()

        corrected_out = list(job.load_output('particles'))
        cs_data = {
            'particles':          corrected_out,
            'global_ctf_applied': True
        }

        stats = job.doc.get('output_stats', {})
        beam_tilt_x_mrad         = stats.get('beam_tilt_x_mrad', 0.0)
        beam_tilt_y_mrad         = stats.get('beam_tilt_y_mrad', 0.0)
        beam_tilt_magnitude_mrad = (beam_tilt_x_mrad**2 + beam_tilt_y_mrad**2) ** 0.5
        anisomag_xx              = stats.get('anisomag_xx', 1.0)
        anisomag_yy              = stats.get('anisomag_yy', 1.0)
        anisomag_xy              = stats.get('anisomag_xy', 0.0)
        trefoil_amplitude_mrad   = stats.get('trefoil_amplitude_mrad', 0.0)
        trefoil_angle_degrees    = stats.get('trefoil_angle_degrees', 0.0)
        cs_original_mm           = stats.get('cs_original_mm', 2.7)
        cs_refined_mm            = stats.get('cs_refined_mm', cs_original_mm)
        resolution_after         = stats.get('fsc_resolution_0143', resolution_before)
        resolution_improvement   = round(resolution_before - resolution_after, 3)

        with open('particles_global_ctf.cs', 'w') as f:
            json.dump(cs_data, f, indent=2)
    else:
        raise RuntimeError(
            "CryoSPARC connection required. Set --use_cryosparc true and provide "
            "CryoSPARC connection params."
        )

    report = {
        'step':                          'global_ctf_refinement',
        'timestamp':                     datetime.now().isoformat(),
        'num_particles':                 num_particles,

        # Beam tilt
        'fit_tilt':                      fit_tilt,
        'beam_tilt_x_mrad':              beam_tilt_x_mrad,
        'beam_tilt_y_mrad':              beam_tilt_y_mrad,
        'beam_tilt_magnitude_mrad':      round(beam_tilt_magnitude_mrad, 4),

        # Anisotropic magnification
        'fit_anisomag':                  fit_anisomag,
        'anisomag_correction_applied':   fit_anisomag,
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
        'resolution_improvement_angstroms': resolution_improvement
    }

    with open('global_ctf_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Global CTF refinement complete")
    print(f"  Particles    : {num_particles}")
    if fit_tilt:
        print(f"  Beam tilt    : x={beam_tilt_x_mrad:.3f} mrad, y={beam_tilt_y_mrad:.3f} mrad")
    if fit_anisomag:
        print(f"  Anisomag     : applied")
    print(f"  Resolution   : {resolution_before:.2f} A -> {resolution_after:.2f} A")
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
