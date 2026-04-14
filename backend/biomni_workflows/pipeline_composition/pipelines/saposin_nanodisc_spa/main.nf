#!/usr/bin/env nextflow
/*
 * saposin_nanodisc_spa -- CryoSPARC SPA optimized for small membrane proteins
 *                          in saposin A nanodisc (< 60 kDa, 0.649 A/pix)
 *
 * Protocol derived from:
 *   Lee et al. MFSD2B preprint 2025 (saposin, 0.649 A/pix, 60 e/A2)
 *   Lee et al. VMAT2 Nature 2023 (saposin, dual-dataset, 50 kDa class)
 *
 * Key differences from cryosparc_standard_spa:
 *   1. pixel_size default = 0.649 A/pix (mandatory for < 60 kDa)
 *   2. total_dose = 60 e-/A2 (small particle, needs more dose)
 *   3. box_size = 256 px (10 nm nanodisc at 0.649 A/pix)
 *   4. Saposin QC step: validate nanodisc size + SEC peak
 *   5. TOPAZ training pass after initial blob-pick 2D classes
 *
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters -- saposin nanodisc defaults
// ============================================================================

params.movies_path                  = null
params.gain_ref                     = null
params.outdir                       = './results/saposin_nanodisc_spa'
params.project_name                 = 'biomate_saposin_spa'

// Saposin-specific collection parameters (from literature)
params.pixel_size                   = 0.649   // MANDATORY for < 60 kDa
params.voltage                      = 300
params.spherical_aberration         = 2.7
params.total_dose                   = 60.0    // Higher dose for small particles
params.dose_per_frame               = null
params.box_size_px                  = 256     // 256 px at 0.649 A/pix = ~16.6 nm
params.defocus_min_um               = -0.8
params.defocus_max_um               = -2.0
params.symmetry                     = 'C1'

// Sample information
params.molecular_weight_kda         = null    // must be < 60
params.sample_name                  = 'membrane_protein'
params.lipid_mix                    = 'POPC:POPE:POPG'  // default for most MPs
params.lipid_ratio                  = '3:1:1'

// Saposin reconstitution QC parameters
params.expected_nanodisc_nm         = 10.0    // expected diameter
params.nanodisc_size_tolerance_nm   = 2.0     // +-2 nm acceptable
params.sec_single_peak_required     = true    // abort if SEC shows aggregates

// TOPAZ training
params.run_topaz_training           = true
params.topaz_min_particles_for_train = 500    // need >= 500 good 2D classes
params.topaz_model_radius           = 8       // 8 px at 0.649 A/pix for ~10 nm disc

// CryoSPARC connection
params.use_cryosparc                = false
params.cryosparc_license            = null
params.cryosparc_host               = 'localhost'
params.cryosparc_port               = 39000
params.cryosparc_lane               = 'default'

// Pipeline config
params.num_ab_initio_classes        = 3
params.max_resolution_refinement    = 2.5
params.gpu_memory_gb                = 16
params.invocation_id                = 'inv_unknown'

// ============================================================================
// Module imports
// ============================================================================

include { SAPOSIN_RECONSTITUTION_QC     } from '../../modules/cryo_em_tools/saposin_qc.nf'
include { IMPORT_MOVIES                 } from '../../modules/cryosparc/import_movies.nf'
include { PATCH_MOTION_CORRECTION       } from '../../modules/cryosparc/patch_motion_correction.nf'
include { PATCH_CTF_ESTIMATION          } from '../../modules/cryosparc/patch_ctf_estimation.nf'
include { MICROGRAPH_DENOISER           } from '../../modules/cryosparc/micrograph_denoiser.nf'
include { BLOB_PICKER                   } from '../../modules/cryosparc/blob_picker.nf'
include { INSPECT_PICKS;
          INSPECT_PICKS_R2              } from '../../modules/cryosparc/inspect_picks.nf'
include { EXTRACT_PARTICLES_R1;
          EXTRACT_PARTICLES_R2          } from '../../modules/cryosparc/extract_particles.nf'
include { CLASSIFY_2D_R1;
          CLASSIFY_2D_R2                } from '../../modules/cryosparc/classify_2d.nf'
include { SELECT_2D_R1;
          SELECT_2D_R2                  } from '../../modules/cryosparc/select_2d.nf'
include { TEMPLATE_PICKER               } from '../../modules/cryosparc/template_picker.nf'
include { AB_INITIO                     } from '../../modules/cryosparc/ab_initio.nf'
include { HOMOGENEOUS_REFINEMENT        } from '../../modules/cryosparc/homogeneous_refinement.nf'
include { LOCAL_CTF_REFINEMENT          } from '../../modules/cryosparc/local_ctf_refinement.nf'
include { NON_UNIFORM_REFINEMENT        } from '../../modules/cryosparc/non_uniform_refinement.nf'
include { LOCAL_RESOLUTION              } from '../../modules/cryosparc/local_resolution.nf'
include { SHARPEN                       } from '../../modules/cryosparc/sharpen.nf'
include { VALIDATION_FSC                } from '../../modules/cryosparc/validation_fsc.nf'
include { PIPELINE_MANIFEST             } from '../../modules/pipeline_manifest.nf'

// ============================================================================
// Validation
// ============================================================================

def validateParams() {
    if (params.molecular_weight_kda != null && params.molecular_weight_kda > 60) {
        log.warn """
        WARNING: molecular_weight_kda=${params.molecular_weight_kda} kDa exceeds 60 kDa.
        Saposin nanodisc protocol is optimized for < 60 kDa membrane proteins.
        Consider: msp_nanodisc_gpcr for GPCR-G protein complexes (100-150 kDa)
                  cryosparc_standard_spa for general SPA (> 60 kDa)
        Continuing with saposin protocol, but review pixel_size=${params.pixel_size}.
        """.stripIndent()
    }
    if (params.pixel_size > 0.83) {
        error "pixel_size=${params.pixel_size} is too large for saposin nanodisc SPA. Use 0.649 A/pix."
    }
}

// ============================================================================
// Main workflow
// ============================================================================

workflow {
    validateParams()

    // Step 0: Saposin reconstitution QC
    // Validates nanodisc preparation before committing to data collection
    qc_input = Channel.value([
        params.sample_name,
        params.lipid_mix,
        params.lipid_ratio,
        params.expected_nanodisc_nm,
        params.nanodisc_size_tolerance_nm,
        params.sec_single_peak_required,
    ])

    SAPOSIN_RECONSTITUTION_QC(qc_input)

    // Abort if reconstitution QC fails (gating function)
    SAPOSIN_RECONSTITUTION_QC.out.qc_pass
        .filter { !it }
        .subscribe {
            error "Saposin reconstitution QC FAILED. Do NOT proceed to cryo-EM grid prep. Check nanodisc size and SEC profile."
        }

    // Step 1-3: Import, motion correction, CTF
    movies_ch = params.movies_path
        ? Channel.fromPath(params.movies_path, checkIfExists: true)
        : Channel.value('mock_movies')

    IMPORT_MOVIES(movies_ch, params)
    PATCH_MOTION_CORRECTION(IMPORT_MOVIES.out.movies, params)
    PATCH_CTF_ESTIMATION(PATCH_MOTION_CORRECTION.out.micrographs, params)
    MICROGRAPH_DENOISER(PATCH_MOTION_CORRECTION.out.micrographs, params)

    // Step 4-6: Blob picking round 1 (seeds TOPAZ training)
    BLOB_PICKER(PATCH_CTF_ESTIMATION.out.ctf, params.box_size_px, params)
    INSPECT_PICKS(BLOB_PICKER.out.picks, params)
    EXTRACT_PARTICLES_R1(INSPECT_PICKS.out.accepted_picks, params)
    CLASSIFY_2D_R1(EXTRACT_PARTICLES_R1.out.particles, params)
    SELECT_2D_R1(CLASSIFY_2D_R1.out.classes, params)

    // Step 7: TOPAZ training on round-1 good 2D classes
    // (if run_topaz_training=true and enough particles available)
    if (params.run_topaz_training) {
        TEMPLATE_PICKER(
            SELECT_2D_R1.out.selected_particles,
            PATCH_CTF_ESTIMATION.out.ctf,
            params
        )
        INSPECT_PICKS_R2(TEMPLATE_PICKER.out.picks, params)
        EXTRACT_PARTICLES_R2(INSPECT_PICKS_R2.out.accepted_picks, params)
        CLASSIFY_2D_R2(EXTRACT_PARTICLES_R2.out.particles, params)
        SELECT_2D_R2(CLASSIFY_2D_R2.out.classes, params)
        final_particles = SELECT_2D_R2.out.selected_particles
    } else {
        final_particles = SELECT_2D_R1.out.selected_particles
    }

    // Step 8-13: Refinement pipeline
    AB_INITIO(final_particles, params)
    HOMOGENEOUS_REFINEMENT(AB_INITIO.out.volume, final_particles, params)
    LOCAL_CTF_REFINEMENT(HOMOGENEOUS_REFINEMENT.out.particles, params)
    NON_UNIFORM_REFINEMENT(LOCAL_CTF_REFINEMENT.out.particles, HOMOGENEOUS_REFINEMENT.out.volume, params)
    LOCAL_RESOLUTION(NON_UNIFORM_REFINEMENT.out.volume, params)
    SHARPEN(NON_UNIFORM_REFINEMENT.out.volume, LOCAL_RESOLUTION.out.local_res, params)
    VALIDATION_FSC(NON_UNIFORM_REFINEMENT.out.half_maps, params)

    // Manifest / report
    all_outputs = SHARPEN.out.sharpened_map
        .mix(VALIDATION_FSC.out.fsc_curve)
        .mix(LOCAL_RESOLUTION.out.local_res_map)
        .mix(SAPOSIN_RECONSTITUTION_QC.out.qc_report)
        .collect()

    PIPELINE_MANIFEST(all_outputs, params)
}
