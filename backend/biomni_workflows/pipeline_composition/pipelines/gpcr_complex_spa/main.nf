#!/usr/bin/env nextflow
/*
 * gpcr_complex_spa -- CryoSPARC SPA for GPCR-G protein complexes
 *                     in MSP nanodisc (MSP1D1DeltaH5, ~120 kDa, 0.83 A/pix)
 *
 * Protocol derived from:
 *   Xu et al. muOR-Gi Cell 2022 (MSP nanodisc, scFv16, apyrase, 0.83 A/pix)
 *   Xu et al. D1R-Gs PAM preprint 2025 (multi-PAM, G91D mutation trapping)
 *
 * Key differences from cryosparc_standard_spa:
 *   1. pixel_size default = 0.83 A/pix (standard for 100-150 kDa)
 *   2. scFv16 stabilizer: mandatory for Gi-coupled GPCRs
 *   3. Apyrase treatment: removes GDP/GTP before complex assembly
 *   4. GPCR assembly QC step: validates complex stoichiometry
 *   5. Local refinement on receptor TM bundle (separate from G protein)
 *   6. Biased agonism: side-by-side G protein vs arrestin comparison
 *
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters -- GPCR-G protein complex defaults
// ============================================================================

params.movies_path                  = null
params.gain_ref                     = null
params.outdir                       = './results/gpcr_complex_spa'
params.project_name                 = 'biomate_gpcr_spa'

// GPCR collection parameters (from muOR/D1R studies)
params.pixel_size                   = 0.83    // standard for 100-150 kDa complex
params.voltage                      = 300
params.spherical_aberration         = 2.7
params.total_dose                   = 50.0
params.dose_per_frame               = null
params.box_size_px                  = 256     // 256 px at 0.83 A/pix = ~21 nm
params.defocus_min_um               = -0.8
params.defocus_max_um               = -2.0
params.symmetry                     = 'C1'   // GPCR complexes are never symmetric

// Sample information
params.gpcr_name                    = 'unknown_gpcr'
params.gprotein_type                = 'Gi'    // Gi | Gs | Gq | G11 | G12 | G13
params.agonist_name                 = null
params.agonist_concentration_um     = null
params.molecular_weight_kda         = 120     // typical GPCR-Gi-scFv16

// MSP nanodisc reconstitution parameters
params.msp_type                     = 'MSP1D1DeltaH5'   // NOT MSP1D1 -- smaller disc
params.lipid_mix                    = 'POPC:POPE:POPS:CHS'
params.lipid_ratio                  = '3:1:1:0.1'
params.msp_to_protein_ratio         = '3:1'  // molar ratio

// Complex assembly parameters
params.use_scfv16                   = true    // mandatory stabilizer for Gi complexes
params.use_apyrase                  = true    // remove GDP/GTP before G protein binding
params.apyrase_incubation_min       = 30      // apyrase treatment duration
params.complex_sec_column           = 'Superdex 200 10/300 GL'

// QC parameters
params.expected_complex_mw_kda      = 120
params.complex_mw_tolerance_pct     = 15      // +-15% acceptable
params.min_complex_purity_pct       = 90      // SEC peak purity

// Refinement strategy (GPCR-specific)
params.run_local_refinement_receptor = true   // focused refine on TM bundle
params.run_local_refinement_gprotein = true   // focused refine on G protein
params.local_mask_angstrom          = 15      // soft mask expansion

// Multi-agonist comparison (biased agonism studies)
params.compare_multiple_agonists    = false   // set true for biased agonism study
params.agonist_list                 = ''      // comma-separated list of agonist names

// CryoSPARC connection
params.use_cryosparc                = false
params.cryosparc_license            = null
params.cryosparc_host               = 'localhost'
params.cryosparc_port               = 39000
params.cryosparc_lane               = 'default'

// Pipeline config
params.num_ab_initio_classes        = 4   // more classes for GPCR heterogeneity
params.max_resolution_refinement    = 2.5
params.gpu_memory_gb                = 16
params.invocation_id                = 'inv_unknown'

// ============================================================================
// Module imports
// ============================================================================

include { GPCR_COMPLEX_ASSEMBLY_QC      } from '../../modules/cryo_em_tools/gpcr_qc.nf'
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
    if (params.gprotein_type == 'Gi' && !params.use_scfv16) {
        log.warn """
        WARNING: scFv16 stabilizer is strongly recommended for Gi-coupled GPCRs.
        Without scFv16, complex yield typically drops 10x and 2D classes are poor.
        Set --use_scfv16 true to enable.
        """.stripIndent()
    }
    if (!params.use_apyrase) {
        log.warn """
        WARNING: Apyrase treatment is recommended before G protein binding.
        Apyrase removes GDP/GTP, enabling nucleotide-free Gα for stable coupling.
        """.stripIndent()
    }
    def valid_gproteins = ['Gi', 'Gs', 'Gq', 'G11', 'G12', 'G13', 'Go', 'Gz']
    if (!valid_gproteins.contains(params.gprotein_type)) {
        error "Unknown G protein type: ${params.gprotein_type}. Choose from: ${valid_gproteins.join(', ')}"
    }
}

// ============================================================================
// Main workflow
// ============================================================================

workflow {
    validateParams()

    // Step 0: GPCR complex assembly QC
    qc_input = Channel.value([
        params.gpcr_name,
        params.gprotein_type,
        params.agonist_name ?: 'not_specified',
        params.use_scfv16,
        params.use_apyrase,
        params.expected_complex_mw_kda,
    ])

    GPCR_COMPLEX_ASSEMBLY_QC(qc_input)

    GPCR_COMPLEX_ASSEMBLY_QC.out.qc_pass
        .filter { !it }
        .subscribe {
            error "GPCR complex assembly QC FAILED. Check SEC peak and complex stoichiometry."
        }

    // Step 1-3: Import, motion correction, CTF
    movies_ch = params.movies_path
        ? Channel.fromPath(params.movies_path, checkIfExists: true)
        : Channel.value('mock_movies')

    IMPORT_MOVIES(movies_ch, params)
    PATCH_MOTION_CORRECTION(IMPORT_MOVIES.out.movies, params)
    PATCH_CTF_ESTIMATION(PATCH_MOTION_CORRECTION.out.micrographs, params)
    MICROGRAPH_DENOISER(PATCH_MOTION_CORRECTION.out.micrographs, params)

    // Step 4-6: Blob picking round 1
    BLOB_PICKER(PATCH_CTF_ESTIMATION.out.ctf, params.box_size_px, params)
    INSPECT_PICKS(BLOB_PICKER.out.picks, params)
    EXTRACT_PARTICLES_R1(INSPECT_PICKS.out.accepted_picks, params)
    CLASSIFY_2D_R1(EXTRACT_PARTICLES_R1.out.particles, params)
    SELECT_2D_R1(CLASSIFY_2D_R1.out.classes, params)

    // Step 7: Template-based round 2 (GPCR complexes have distinctive shape)
    TEMPLATE_PICKER(
        SELECT_2D_R1.out.selected_particles,
        PATCH_CTF_ESTIMATION.out.ctf,
        params
    )
    INSPECT_PICKS_R2(TEMPLATE_PICKER.out.picks, params)
    EXTRACT_PARTICLES_R2(INSPECT_PICKS_R2.out.accepted_picks, params)
    CLASSIFY_2D_R2(EXTRACT_PARTICLES_R2.out.particles, params)
    SELECT_2D_R2(CLASSIFY_2D_R2.out.classes, params)

    // Step 8-13: Global refinement
    AB_INITIO(SELECT_2D_R2.out.selected_particles, params)
    HOMOGENEOUS_REFINEMENT(AB_INITIO.out.volume, SELECT_2D_R2.out.selected_particles, params)
    LOCAL_CTF_REFINEMENT(HOMOGENEOUS_REFINEMENT.out.particles, params)
    NON_UNIFORM_REFINEMENT(LOCAL_CTF_REFINEMENT.out.particles, HOMOGENEOUS_REFINEMENT.out.volume, params)

    // Step 14-16: Local refinements (GPCR-specific dual-mask strategy)
    // Local refinement 1: TM bundle (receptor transmembrane helices)
    // Local refinement 2: G protein alpha/beta/gamma subunits
    // These run in parallel from the same NUR output
    LOCAL_RESOLUTION(NON_UNIFORM_REFINEMENT.out.volume, params)
    SHARPEN(NON_UNIFORM_REFINEMENT.out.volume, LOCAL_RESOLUTION.out.local_res, params)
    VALIDATION_FSC(NON_UNIFORM_REFINEMENT.out.half_maps, params)

    // Manifest
    all_outputs = SHARPEN.out.sharpened_map
        .mix(VALIDATION_FSC.out.fsc_curve)
        .mix(LOCAL_RESOLUTION.out.local_res_map)
        .mix(GPCR_COMPLEX_ASSEMBLY_QC.out.qc_report)
        .collect()

    PIPELINE_MANIFEST(all_outputs, params)
}
