#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_batch_register_images
 * Batch register multiple images to a reference using progressive registration (rigid -> affine -> deformable). Uses quick_rigid_registration, quick_affine_registration, and quick_deformable_registration internally.
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.reference_image = null
params.registration_type = null
params.use_gpu = null

// Processes
process COMPILE_REGISTRATION_RESULTS {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(moving_images)
    path(reference_image)
    path(registration_type)
    path(rigid_results)
    path(affine_results)
    path(deformable_results)

    output:
    path("compile_registration_results_metrics.txt"), emit: metrics
    path("compile_registration_results_registered_images.txt"), emit: registered_images

    script:
    """
    # Tool: biomni_bioimaging_batch_register_images
    # Runs in unified Docker container
    echo 'Running COMPILE_REGISTRATION_RESULTS'
        touch compile_registration_results_metrics.txt
    touch compile_registration_results_registered_images.txt
    """
}

workflow BIOMNI_BIOIMAGING_BATCH_REGISTER_IMAGES {
    main:
    ch_reference_image = Channel.fromPath(params.reference_image)
    ch_registration_type = Channel.value(params.registration_type)
    ch_use_gpu = Channel.value(params.use_gpu)

    COMPILE_REGISTRATION_RESULTS(MOVING_IMAGES.out.output, ch_reference_image, ch_registration_type, STEP_1__RIGID_REGISTRATION.out.registered_image, STEP_2__AFFINE_REGISTRATION.out.registered_image, STEP_3__DEFORMABLE_REGISTRATION.out.registered_image)

    emit:
    output = COMPILE_REGISTRATION_RESULTS.out.metrics
}

workflow {
    BIOMNI_BIOIMAGING_BATCH_REGISTER_IMAGES()
}