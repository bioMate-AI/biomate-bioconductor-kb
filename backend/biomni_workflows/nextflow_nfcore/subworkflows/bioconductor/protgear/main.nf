#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: protGear
// A generic three-step pre-processing package for protein microarray data. This package contains diffe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/protGear/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("protGear")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROTGEAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-protgear"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-protgear:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-protgear:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_protgear_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_protgear_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_protgear_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(protGear)
    library(jsonlite)

    # --- Data Loading and Background Extraction [] ---
    # Key functions: read_array_files, name_of_files, extract_bg
    filenames <- list.files(
        file.path(genepix_vars$paths[[1]]),
        pattern = "*.txt$|*.gpr$",
        full.names = FALSE
    )
    data_path <- paste0(genepix_vars$paths[[1]], "/")
    data_files <- purrr::map(
        .x = filenames,
        .f = read_array_files,
        data_path = data_path,
        genepix_vars = genepix_vars
    )
    names(data_files) <- purrr::map_chr(filenames, name_of_files)
    dfs <- names(data_files)
    allData_bg <- purrr::map(
        .x = dfs,
        .f = extract_bg,
        data_files = data_files,
        genepix_vars = genepix_vars
    )
    names(allData_bg) <- purrr::map_chr(filenames, name_of_files)
    allData_bg_df <- plyr::ldply(allData_bg)


    # --- Background Correction and Buffer Spot Analysis [] ---
    # Key functions: merge_sampleID, buffer_spots, plot_buffer
    sample_ID_merged_dfs <- purrr::map(
        .x = dfs,
        .f = merge_sampleID,
        data_files = data_files,
        genepix_vars = genepix_vars,
        method = "subtract_local"
    )
    names(sample_ID_merged_dfs) <- purrr::map_chr(filenames, name_of_files)
    buffer_transp <- purrr::map(
        .x = sample_ID_merged_dfs,
        .f = buffer_spots,
        buffer_spot = "buffer"
    )
    names(buffer_transp) <- purrr::map_chr(filenames, name_of_files)
    buffers <- plyr::ldply(buffer_transp)
    plot_buffer(
        buffers,
        buffer_names = "antigen",
        buffer_mfi = "FMedianBG_correct",
        slide_id = ".id"
    )


    # --- Coefficient of Variation Estimation [] ---
    # Key functions: cv_estimation, cv_by_sample_estimation
    dataCV <- purrr::map(
        .x = sample_ID_merged_dfs,
        .f = cv_estimation,
        lab_replicates = 3,
        cv_cut_off = 20,
        sampleID_var = "sampleID",
        antigen_var = "antigen",
        replicate_var = "replicate",
        mfi_var = "FMedianBG_correct"
    )
    names(dataCV) <- purrr::map_chr(filenames, name_of_files)
    dataCV_sample <- purrr::map(
        .x = dataCV,
        .f = cv_by_sample_estimation,
        cv_variable = "cvCat_all",
        lab_replicates = 3
    )
    names(dataCV_sample) <- purrr::map_chr(filenames, name_of_files)
    all_cv_sample <- plyr::ldply(dataCV_sample)


    # --- Replicate Selection and Best CV Estimation [] ---
    # Key functions: best_CV_estimation, name_of_files
    dataCV_best2 <- purrr::map(
        .x = dataCV,
        .f = best_CV_estimation,
        slide_id = "iden",
        lab_replicates = 3,
        cv_cut_off = 20
    )
    names(dataCV_best2) <- purrr::map_chr(filenames, name_of_files)
    best2_df <- plyr::ldply(dataCV_best2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_protgear_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_protgear_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_protgear_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROTGEAR:", paste0("    protgear: ", packageVersion("protGear"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protgear_results.csv
    touch ${prefix}_protgear_output.rds
    echo "BIOC_PROTGEAR:" > versions.yml
    echo "    protgear: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROTGEAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROTGEAR(ch_input)

    emit:
    results  = BIOC_PROTGEAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROTGEAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROTGEAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROTGEAR.out.versions  // channel: path(versions.yml)
}
