#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: synapsis
// Synapsis is a Bioconductor software package for automated (unbiased and reproducible) analysis of me
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/synapsis/inst/doc/synapsis_tutorial.R
// Upstream  : EBImage, devtools
// Downstream: none
//
// Install: BiocManager::install("synapsis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYNAPSIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-synapsis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-synapsis:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-synapsis:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_synapsis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_synapsis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_synapsis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(synapsis)
    library(jsonlite)

    # --- Size [] ---
    # Key functions: size
    ---------------------------------------------------------------------
    mb = 1e06
    cat("file size in mb:", file.size(file_MLH3)/mb, sep = " ")
    # --- Crop Images [] ---
    # Key functions: auto_crop_fast
    ---------------------------------------------------------------------
    auto_crop_fast(path, annotation = "on", max_cell_area = 30000, min_cell_area = 7000, file_ext = "tif")
    # --- Unlink [] ---
    # Key functions: unlink
    ---------------------------------------------------------------------
    unlink(paste0(path,"/crops-RGB/"), recursive = TRUE)
    unlink(paste0(path,"/crops/"), recursive = TRUE)
    # --- Crop Images [] ---
    # Key functions: auto_crop_fast
    ---------------------------------------------------------------------
    auto_crop_fast(path, annotation = "on", max_cell_area = 30000, min_cell_area = 7000, file_ext = "tif",crowded_cells = TRUE)
    # --- Identify Pachytene Cells [] ---
    # Key functions: get_pachytene
    ---------------------------------------------------------------------
    SYCP3_stats <- get_pachytene(path,ecc_thresh = 0.8, area_thresh = 0.04, annotation = "on",file_ext = "tif")
    # --- Count Foci [] ---
    # Key functions: count_foci
    ---------------------------------------------------------------------
    foci_counts <- count_foci(path,offset_factor = 8, brush_size = 3, offset_px = 0.6, brush_sigma = 3, annotation = "on", stage = "pachytene",file_ext = "tif", watershed_stop= "on",  crowded_foci = FALSE, C1 = 0.03, disc_size_foci = 9)
    # --- Unlink [] ---
    # Key functions: unlink
    ---------------------------------------------------------------------
    unlink(paste0(path,"/crops-RGB/"), recursive = TRUE)
    unlink(paste0(path,"/crops/"), recursive = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_synapsis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_synapsis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_synapsis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SYNAPSIS:", paste0("    synapsis: ", packageVersion("synapsis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_synapsis_results.csv
    touch ${prefix}_synapsis_output.rds
    echo "BIOC_SYNAPSIS:" > versions.yml
    echo "    synapsis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SYNAPSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SYNAPSIS(ch_input)

    emit:
    results  = BIOC_SYNAPSIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SYNAPSIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SYNAPSIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SYNAPSIS.out.versions  // channel: path(versions.yml)
}
