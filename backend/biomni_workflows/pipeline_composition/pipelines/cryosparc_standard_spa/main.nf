#!/usr/bin/env nextflow
/*
 * Staged Pipeline: cryosparc_standard_spa (Phase 3 — module-based)
 *
 * All 23 processes are imported from individual modules/ files.
 * PIPELINE_MANIFEST writes workflow_outputs.json at completion.
 *
 * This replaces the 1612-line production monolith.
 * Promotion criteria (Phase 5): all regression tests pass.
 *
 * To run in mock mode:
 *   nextflow run pipelines/cryosparc_standard_spa/main.nf -stub-run \
 *     --pixel_size 1.05 --voltage 300 --outdir /tmp/spa_staged/
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters (identical to production pipeline)
// ============================================================================

params.movies_path                      = null
params.gain_ref                         = null
params.outdir                           = './results/cryosparc_spa'
params.project_name                     = 'biomate_spa'
params.pixel_size                       = 1.05
params.voltage                          = 300
params.spherical_aberration             = 2.7
params.total_dose                        = 50.0
params.dose_per_frame                   = null
params.sample_type                      = 'unknown'
params.particle_diameter_angstroms      = null
params.molecular_weight_kda             = null
params.symmetry                         = 'C1'
params.phase_plate                      = false
params.mock_mode                        = true
params.use_cryosparc                    = false
params.cryosparc_license                = null
params.cryosparc_host                   = 'localhost'
params.cryosparc_port                   = 39000
params.cryosparc_lane                   = 'default'
params.motion_correction_dose_weighting = true
params.ctf_fitting_resolution_min       = 30.0
params.ctf_fitting_resolution_max       = 5.0
params.particle_box_size                = null
params.num_ab_initio_classes            = 3
params.max_resolution_refinement        = 2.5
params.gpu_memory_gb                    = 16
params.enable_low_memory_mode           = false
params.invocation_id                    = 'inv_unknown'
params.qc_profile                       = 'cryoem_spa_standard'

// ============================================================================
// Module imports
// ============================================================================

include { IMPORT_MOVIES           } from '../../modules/cryosparc/import_movies.nf'
include { PATCH_MOTION_CORRECTION } from '../../modules/cryosparc/patch_motion_correction.nf'
include { PATCH_CTF_ESTIMATION    } from '../../modules/cryosparc/patch_ctf_estimation.nf'
include { MICROGRAPH_DENOISER     } from '../../modules/cryosparc/micrograph_denoiser.nf'
include { BLOB_PICKER             } from '../../modules/cryosparc/blob_picker.nf'
include { JUNK_2D_DETECTOR        } from '../../modules/cryosparc/junk_2d_detector.nf'
include { INSPECT_PICKS;
          INSPECT_PICKS_R2        } from '../../modules/cryosparc/inspect_picks.nf'
include { EXTRACT_PARTICLES_R1;
          EXTRACT_PARTICLES_R2    } from '../../modules/cryosparc/extract_particles.nf'
include { CLASSIFY_2D_R1;
          CLASSIFY_2D_R2          } from '../../modules/cryosparc/classify_2d.nf'
include { SELECT_2D_R1;
          SELECT_2D_R2            } from '../../modules/cryosparc/select_2d.nf'
include { TEMPLATE_PICKER         } from '../../modules/cryosparc/template_picker.nf'
include { AB_INITIO               } from '../../modules/cryosparc/ab_initio.nf'
include { HOMOGENEOUS_REFINEMENT  } from '../../modules/cryosparc/homogeneous_refinement.nf'
include { VOLUME_TOOLS            } from '../../modules/cryosparc/volume_tools.nf'
include { VALIDATION_FSC          } from '../../modules/cryosparc/validation_fsc.nf'
include { LOCAL_CTF_REFINEMENT    } from '../../modules/cryosparc/local_ctf_refinement.nf'
include { NON_UNIFORM_REFINEMENT  } from '../../modules/cryosparc/non_uniform_refinement.nf'
include { LOCAL_RESOLUTION        } from '../../modules/cryosparc/local_resolution.nf'
include { SHARPEN                 } from '../../modules/cryosparc/sharpen.nf'
include { PIPELINE_MANIFEST       } from '../../modules/pipeline_manifest.nf'

// ============================================================================
// Helper functions (used at workflow level for param derivation)
// ============================================================================

def estimate_particle_diameter(mw_kda) {
    if (mw_kda == null) return null
    return (6.8 * Math.pow(mw_kda, 1.0/3.0)).round(1)
}

def estimate_box_size(diameter_angstroms, pixel_size) {
    if (diameter_angstroms == null) return 256
    def min_box = diameter_angstroms * 1.8 / pixel_size
    def powers = [64, 96, 128, 192, 256, 320, 384, 440, 512, 640, 768, 896, 1024]
    return powers.find { it >= min_box } ?: 256
}

def get_sample_recommendations(sample_type) {
    def recommendations = [
        membrane_protein: [num_2d_classes: 100, class_similarity_threshold: 0.3,
                           ab_initio_iterations: 100, refinement_mask_threshold: 0.5,
                           notes: 'Membrane proteins have detergent micelle, need more classes'],
        virus:           [num_2d_classes: 50,  class_similarity_threshold: 0.2,
                           ab_initio_iterations: 50,  refinement_mask_threshold: 0.4,
                           notes: 'Virus particles are symmetric and homogeneous'],
        ribosome:        [num_2d_classes: 200, class_similarity_threshold: 0.4,
                           ab_initio_iterations: 150, refinement_mask_threshold: 0.35,
                           notes: 'Ribosomes show conformational heterogeneity'],
        small_protein:   [num_2d_classes: 100, class_similarity_threshold: 0.25,
                           ab_initio_iterations: 100, refinement_mask_threshold: 0.45,
                           notes: 'Small proteins may have lower SNR, need more averaging'],
        unknown:         [num_2d_classes: 100, class_similarity_threshold: 0.3,
                           ab_initio_iterations: 100, refinement_mask_threshold: 0.4,
                           notes: 'Default conservative settings'],
    ]
    return recommendations[sample_type] ?: recommendations['unknown']
}

// Port paths — relative to outdir, matching production pipeline publishDir layout
def SPA_PORTS = [
    "particles_ctf_refined": "20_local_ctf_refinement/particles_ctf_refined.cs",
    "volume_cs":             "17_homogeneous_refinement/refined_volume.cs",
    "nu_refined_volume":     "21_non_uniform_refinement/volume_nu_refined.mrc",
    "sharpened_map":         "23_sharpening/volume_sharpened.mrc",
    "fsc_report":            "19_validation_fsc/validation_report.json",
    "local_resolution_map":  "22_local_resolution/local_resolution.mrc",
    "micrographs_ctf":       "03_ctf_estimation/micrographs_ctf.cs",
]

// ============================================================================
// Named workflow (includable from tests and integration pipelines)
// ============================================================================

workflow CRYOSPARC_STANDARD_SPA {
    take:
    movies_path

    main:
    IMPORT_MOVIES(movies_path)
    PATCH_MOTION_CORRECTION(IMPORT_MOVIES.out.movies_cs)
    PATCH_CTF_ESTIMATION(PATCH_MOTION_CORRECTION.out.micrographs_cs)
    MICROGRAPH_DENOISER(PATCH_CTF_ESTIMATION.out.ctf_cs)
    BLOB_PICKER(MICROGRAPH_DENOISER.out.denoised_cs)
    JUNK_2D_DETECTOR(BLOB_PICKER.out.particles_cs)
    INSPECT_PICKS(JUNK_2D_DETECTOR.out.filtered_cs)
    EXTRACT_PARTICLES_R1(INSPECT_PICKS.out.inspected_cs)
    CLASSIFY_2D_R1(EXTRACT_PARTICLES_R1.out.extracted_cs)
    SELECT_2D_R1(CLASSIFY_2D_R1.out.classes_cs, EXTRACT_PARTICLES_R1.out.extracted_cs)
    TEMPLATE_PICKER(SELECT_2D_R1.out.selected_cs, MICROGRAPH_DENOISER.out.denoised_cs)
    INSPECT_PICKS_R2(TEMPLATE_PICKER.out.template_particles_cs)
    EXTRACT_PARTICLES_R2(INSPECT_PICKS_R2.out.inspected_cs)
    CLASSIFY_2D_R2(EXTRACT_PARTICLES_R2.out.extracted_cs)
    SELECT_2D_R2(CLASSIFY_2D_R2.out.classes_cs, EXTRACT_PARTICLES_R2.out.extracted_cs)
    AB_INITIO(SELECT_2D_R2.out.selected_cs)
    HOMOGENEOUS_REFINEMENT(AB_INITIO.out.volumes_cs, SELECT_2D_R2.out.selected_cs)
    VOLUME_TOOLS(HOMOGENEOUS_REFINEMENT.out.refined_cs)
    VALIDATION_FSC(VOLUME_TOOLS.out.processed_cs)
    LOCAL_CTF_REFINEMENT(SELECT_2D_R2.out.selected_cs, VOLUME_TOOLS.out.processed_cs)
    NON_UNIFORM_REFINEMENT(LOCAL_CTF_REFINEMENT.out.refined_particles_cs, VOLUME_TOOLS.out.processed_cs)
    LOCAL_RESOLUTION(NON_UNIFORM_REFINEMENT.out.final_volume)
    SHARPEN(NON_UNIFORM_REFINEMENT.out.final_volume)

    // Manifest — written after all outputs are produced.
    // Collect final outputs as a trigger channel so PIPELINE_MANIFEST only
    // runs after SHARPEN, LOCAL_RESOLUTION, and VALIDATION_FSC all complete.
    def trigger_ch = SHARPEN.out.sharpened_volume
        .mix(SHARPEN.out.summary)
        .mix(LOCAL_RESOLUTION.out.local_res_map)
        .mix(VALIDATION_FSC.out.fsc)
        .collect()

    def ports_json  = groovy.json.JsonOutput.toJson(SPA_PORTS)
    def params_json = groovy.json.JsonOutput.toJson([
        pixel_size: params.pixel_size,
        voltage:    (int) params.voltage,
        qc_profile: params.qc_profile,
    ])
    PIPELINE_MANIFEST(
        Channel.value("cryosparc_standard_spa"),
        Channel.value(params.invocation_id),
        Channel.value(params.outdir),
        Channel.value(ports_json),
        Channel.value(params_json),
        Channel.value("{}"),
        trigger_ch,
    )

    emit:
    final_map    = SHARPEN.out.sharpened_volume
    local_res    = LOCAL_RESOLUTION.out.local_res_map
    fsc          = VALIDATION_FSC.out.fsc
    summary      = SHARPEN.out.summary
    manifest     = PIPELINE_MANIFEST.out.manifest
}

// ============================================================================
// Standalone entry point
// ============================================================================

workflow {
    if (params.particle_diameter_angstroms == null && params.molecular_weight_kda != null) {
        params.particle_diameter_angstroms = estimate_particle_diameter(params.molecular_weight_kda)
    }
    if (params.particle_box_size == null) {
        params.particle_box_size = estimate_box_size(
            params.particle_diameter_angstroms ?: 150,
            params.pixel_size
        )
    }

    def ch_movies = Channel.fromPath(params.movies_path ?: "${baseDir}/test_data/*.tif")
        .ifEmpty {
            // Always use a local temp directory for dummy input files.
            // params.outdir may be an S3 URL when running on AWS Batch, in which
            // case file("${params.outdir}/...").mkdirs() would fail (no local path).
            def dummy_dir = file("/tmp/biomate_test_movies_${params.invocation_id}")
            dummy_dir.mkdirs()
            (1..20).collect { i ->
                def f = file("${dummy_dir}/movie_${String.format('%05d', i)}.tif")
                f.text = "dummy movie ${i}"
                f
            }
        }
        .collect()

    CRYOSPARC_STANDARD_SPA(ch_movies)
}

workflow.onComplete {
    log.info "Workflow ${workflow.success ? 'SUCCESS' : 'FAILED'} — ${workflow.duration}"
}
