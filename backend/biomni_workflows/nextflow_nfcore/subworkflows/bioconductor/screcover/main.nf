#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scRecover
// scRecover is an R package for imputation of single-cell RNA-seq (scRNA-seq) data. It will detect and
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scRecover/inst/doc/scRecover.R
// Upstream  : BiocParallel, SingleCellExperiment
// Downstream: none
//
// Install: BiocManager::install("scRecover")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCRECOVER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-screcover"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-screcover:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-screcover:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_screcover_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_screcover_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_screcover_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Demo1 [] ---
    # Key functions: scRecover
    # Load test data for scRecover
    data(scRecoverTest)
    # Run scRecover with Kcluster specified
    scRecover(counts = counts, Kcluster = 2, outputDir = "./outDir_scRecover/", verbose = FALSE)
    # Or run scRecover with labels specified
    # --- Demo2 [] ---
    # Key functions: SingleCellExperiment, sce, scRecover
    # Load test data for scRecover
    data(scRecoverTest)
    # Convert the test data in scRecover to SingleCellExperiment data representation
    sce <- SingleCellExperiment(assays = list(counts = as.matrix(counts)))
    # Run scRecover with SingleCellExperiment input sce (Kcluster specified)
    # --- Demo3 [] ---
    # Key functions: countsSampling, estDropoutNum
    # Load test data
    data(scRecoverTest)
    # Downsample 10% read counts in oneCell
    set.seed(999)
    oneCell.down <- countsSampling(counts = oneCell, fraction = 0.1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_screcover_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_screcover_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_screcover_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCRECOVER:", paste0("    screcover: ", packageVersion("scRecover"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_screcover_results.csv
    touch ${prefix}_screcover_output.rds
    echo "BIOC_SCRECOVER:" > versions.yml
    echo "    screcover: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCRECOVER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCRECOVER(ch_input)

    emit:
    results  = BIOC_SCRECOVER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCRECOVER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCRECOVER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCRECOVER.out.versions  // channel: path(versions.yml)
}
