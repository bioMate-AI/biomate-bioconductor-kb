#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: diffcyt
// Statistical methods for differential discovery analyses in high-dimensional cytometry data (includin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/diffcyt/inst/doc/diffcyt_workflow.R
// Upstream  : HDCytoData, flowCore
// Downstream: censcyt, cytofWorkflow
//
// Install: BiocManager::install("diffcyt")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIFFCYT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-diffcyt"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-diffcyt:1.26.1--r44_0' :
        'quay.io/biocontainers/bioconductor-diffcyt:1.26.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_diffcyt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_diffcyt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_diffcyt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(diffcyt)
    library(jsonlite)

    # --- Character [] ---
    # Key functions: pData, factor, frame, setdiff
    ---------------------------------------------------------------------
    # Meta-data: experiment information
    # check sample order
    filenames <- as.character(pData(d_flowSet)$name)
    # sample information
    # --- Createcontrast [] ---
    # Key functions: createContrast, frame
    ---------------------------------------------------------------------
    # Create contrast matrix
    contrast <- createContrast(c(0, 1, rep(0, 7)))
    # check
    nrow(contrast) == ncol(design)
    # --- Abundance [] ---
    # Key functions: abundance, diffcyt, topTable, rate
    ---------------------------------------------------------------------
    # Test for differential abundance (DA) of clusters
    # note: using default method 'diffcyt-DA-edgeR' and default parameters
    # note: include random seed for reproducible clustering
    # --- Preparedata [] ---
    # Key functions: prepareData
    ---------------------------------------------------------------------
    # Prepare data
    d_se <- prepareData(d_flowSet, experiment_info, marker_info)
    # --- Transformdata [] ---
    # Key functions: transformData
    ---------------------------------------------------------------------
    # Transform data
    d_se <- transformData(d_se)
    # --- Generateclusters [] ---
    # Key functions: generateClusters
    ---------------------------------------------------------------------
    # Generate clusters
    # note: include random seed for reproducible clustering
    d_se <- generateClusters(d_se, seed_clustering = 123)
    # --- Calccounts [] ---
    # Key functions: calcCounts, calcMedians
    ---------------------------------------------------------------------
    # Calculate cluster cell counts
    d_counts <- calcCounts(d_se)
    # Calculate cluster medians
    d_medians <- calcMedians(d_se)
    # --- Abundance [] ---
    # Key functions: abundance, testDA_edgeR, topTable, rate
    ---------------------------------------------------------------------
    # Test for differential abundance (DA) of clusters
    res_DA <- testDA_edgeR(d_counts, design, contrast)
    # display table of results for top DA clusters
    topTable(res_DA, format_vals = TRUE)
    # --- Diffcyt [] ---
    # Key functions: diffcyt, rowData, assay
    ---------------------------------------------------------------------
    # Output object from 'diffcyt()' wrapper function
    names(out_DA)
    dim(out_DA$d_se)
    rowData(out_DA$d_se)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_diffcyt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_diffcyt_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_diffcyt_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIFFCYT:", paste0("    diffcyt: ", packageVersion("diffcyt"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diffcyt_results.csv
    touch ${prefix}_diffcyt_output.rds
    echo "BIOC_DIFFCYT:" > versions.yml
    echo "    diffcyt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIFFCYT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIFFCYT(ch_input)

    emit:
    results  = BIOC_DIFFCYT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIFFCYT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIFFCYT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIFFCYT.out.versions  // channel: path(versions.yml)
}
