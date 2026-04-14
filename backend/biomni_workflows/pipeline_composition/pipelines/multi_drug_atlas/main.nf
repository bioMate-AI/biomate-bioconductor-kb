#!/usr/bin/env nextflow
/*
 * multi_drug_atlas -- Multi-drug pharmacology SPA + difference map pipeline
 *
 * Protocol derived from:
 *   Yan et al. CaV1.2 multi-drug Cell 2023 (7 drugs, GDN detergent, 0.83 A/pix)
 *   Xu et al. D1R multi-PAM preprint 2025 (simultaneous PAM combinations)
 *
 * Pipeline:
 *   Phase 1: Collect identical SPA datasets for apo + each drug
 *   Phase 2: Process all datasets through same pipeline (same cryosparc_standard_spa)
 *   Phase 3: Generate difference maps (drug - apo) at ±3sigma threshold
 *   Phase 4: Validate ligand density occupancy
 *   Phase 5: Multi-drug comparison report
 *
 * Key requirement: ALL datasets (apo + drugs) must have IDENTICAL collection
 * parameters (pixel_size, defocus, dose). Process all in the same CryoSPARC project.
 *
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.outdir                       = './results/multi_drug_atlas'
params.project_name                 = 'biomate_drug_atlas'

// Collection parameters (MUST be identical for all datasets)
params.pixel_size                   = 0.83
params.voltage                      = 300
params.spherical_aberration         = 2.7
params.total_dose                   = 50.0
params.box_size_px                  = 320    // for 300-600 kDa ion channels
params.defocus_min_um               = -0.8
params.defocus_max_um               = -2.0
params.symmetry                     = 'C1'

// Drug atlas configuration
params.apo_movies_path              = null   // path to apo dataset movies
params.drug_names                   = ''     // comma-separated: 'verapamil,diltiazem,nifedipine'
params.drug_movies_paths            = ''     // comma-separated paths to each drug dataset
params.drug_concentrations_um       = ''     // comma-separated concentrations
params.num_drugs                    = 3

// Target protein
params.target_name                  = 'ion_channel'
params.molecular_weight_kda         = 400    // typical CaV1.2-like channel
params.detergent                    = 'GDN'  // GDN preferred for ion channels
params.detergent_concentration_pct  = 0.01

// Difference map parameters
params.sigma_threshold              = 3.0    // ±3sigma threshold for ligand density
params.min_occupancy_pct            = 60     // minimum occupancy to report density as real
params.map_resolution_angstrom      = null   // null = auto from FSC

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

include { IMPORT_MOVIES                 } from '../../modules/cryosparc/import_movies.nf'
include { PATCH_MOTION_CORRECTION       } from '../../modules/cryosparc/patch_motion_correction.nf'
include { PATCH_CTF_ESTIMATION          } from '../../modules/cryosparc/patch_ctf_estimation.nf'
include { MICROGRAPH_DENOISER           } from '../../modules/cryosparc/micrograph_denoiser.nf'
include { BLOB_PICKER                   } from '../../modules/cryosparc/blob_picker.nf'
include { INSPECT_PICKS                 } from '../../modules/cryosparc/inspect_picks.nf'
include { EXTRACT_PARTICLES_R1          } from '../../modules/cryosparc/extract_particles.nf'
include { CLASSIFY_2D_R1                } from '../../modules/cryosparc/classify_2d.nf'
include { SELECT_2D_R1                  } from '../../modules/cryosparc/select_2d.nf'
include { TEMPLATE_PICKER               } from '../../modules/cryosparc/template_picker.nf'
include { AB_INITIO                     } from '../../modules/cryosparc/ab_initio.nf'
include { HOMOGENEOUS_REFINEMENT        } from '../../modules/cryosparc/homogeneous_refinement.nf'
include { LOCAL_CTF_REFINEMENT          } from '../../modules/cryosparc/local_ctf_refinement.nf'
include { NON_UNIFORM_REFINEMENT        } from '../../modules/cryosparc/non_uniform_refinement.nf'
include { LOCAL_RESOLUTION              } from '../../modules/cryosparc/local_resolution.nf'
include { SHARPEN                       } from '../../modules/cryosparc/sharpen.nf'
include { VALIDATION_FSC                } from '../../modules/cryosparc/validation_fsc.nf'
include { DRUG_DIFFERENCE_MAP;
          MULTI_DRUG_ATLAS              } from '../../modules/cryo_em_tools/drug_difference_map.nf'
include { PIPELINE_MANIFEST             } from '../../modules/pipeline_manifest.nf'

// ============================================================================
// Helper: run SPA for a single dataset
// ============================================================================

workflow SPA_SINGLE_DATASET {
    take:
    movies_input   // channel: path to movie files
    dataset_label  // val: 'apo' or drug name

    main:
    IMPORT_MOVIES(movies_input, params)
    PATCH_MOTION_CORRECTION(IMPORT_MOVIES.out.movies, params)
    PATCH_CTF_ESTIMATION(PATCH_MOTION_CORRECTION.out.micrographs, params)
    MICROGRAPH_DENOISER(PATCH_MOTION_CORRECTION.out.micrographs, params)
    BLOB_PICKER(PATCH_CTF_ESTIMATION.out.ctf, params.box_size_px, params)
    INSPECT_PICKS(BLOB_PICKER.out.picks, params)
    EXTRACT_PARTICLES_R1(INSPECT_PICKS.out.accepted_picks, params)
    CLASSIFY_2D_R1(EXTRACT_PARTICLES_R1.out.particles, params)
    SELECT_2D_R1(CLASSIFY_2D_R1.out.classes, params)
    TEMPLATE_PICKER(SELECT_2D_R1.out.selected_particles, PATCH_CTF_ESTIMATION.out.ctf, params)
    AB_INITIO(TEMPLATE_PICKER.out.picks, params)
    HOMOGENEOUS_REFINEMENT(AB_INITIO.out.volume, TEMPLATE_PICKER.out.picks, params)
    LOCAL_CTF_REFINEMENT(HOMOGENEOUS_REFINEMENT.out.particles, params)
    NON_UNIFORM_REFINEMENT(LOCAL_CTF_REFINEMENT.out.particles, HOMOGENEOUS_REFINEMENT.out.volume, params)
    LOCAL_RESOLUTION(NON_UNIFORM_REFINEMENT.out.volume, params)
    SHARPEN(NON_UNIFORM_REFINEMENT.out.volume, LOCAL_RESOLUTION.out.local_res, params)
    VALIDATION_FSC(NON_UNIFORM_REFINEMENT.out.half_maps, params)

    emit:
    sharpened_map = SHARPEN.out.sharpened_map
    fsc_curve     = VALIDATION_FSC.out.fsc_curve
    resolution    = VALIDATION_FSC.out.resolution_angstrom
}

// ============================================================================
// Main workflow
// ============================================================================

workflow {
    // Parse movie paths from params
    def drug_list = params.drug_names.split(',').collect { it.trim() }
    def drug_paths = params.drug_movies_paths.split(',').collect { it.trim() }

    if (drug_list.size() != drug_paths.size()) {
        error "drug_names (${drug_list.size()}) and drug_movies_paths (${drug_paths.size()}) must have same length"
    }

    // Process apo dataset
    apo_ch = Channel.fromPath(params.apo_movies_path, checkIfExists: true)
    SPA_SINGLE_DATASET(apo_ch, 'apo')
    apo_map = SPA_SINGLE_DATASET.out.sharpened_map

    // Process each drug dataset in parallel
    drug_ch = Channel.fromList(drug_list.withIndex().collect { name, i ->
        [name, drug_paths[i]]
    }).flatMap { name, path ->
        Channel.fromPath(path, checkIfExists: true).map { f -> [name, f] }
    }

    SPA_SINGLE_DATASET(drug_ch.map { it[1] }, drug_ch.map { it[0] })

    // Difference maps
    SPA_SINGLE_DATASET.out.sharpened_map.combine(apo_map).set { diff_inputs }

    DRUG_DIFFERENCE_MAP(
        diff_inputs,
        params.sigma_threshold
    )

    all_diff = DRUG_DIFFERENCE_MAP.out.difference_map.collect()
    all_rpts  = DRUG_DIFFERENCE_MAP.out.report.collect()

    MULTI_DRUG_ATLAS(
        all_diff,
        all_rpts,
        Channel.value(drug_list.join(',')),
        params.target_name
    )

    PIPELINE_MANIFEST(
        MULTI_DRUG_ATLAS.out.atlas_report.mix(all_diff).collect(),
        params
    )
}
