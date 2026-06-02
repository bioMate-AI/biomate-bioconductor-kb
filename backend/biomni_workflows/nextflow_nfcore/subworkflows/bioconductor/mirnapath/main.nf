#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: miRNApath
// This package provides pathway enrichment techniques for miRNA expression data. Specifically, the set
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/miRNApath/inst/doc/miRNApath.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("miRNApath")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRNAPATH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mirnapath"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mirnapath:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mirnapath:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mirnapath_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mirnapath_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mirnapath_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(miRNApath)
    library(jsonlite)

    # --- Pathway Matrix Extraction [] ---
    # Key functions: mirnaTable
    pathwaycol <- mirnaobj@columns["pathwaycol"]
    pathwayidcol <- mirnaobj@columns["pathwayidcol"]
    rownames(widetable) <- apply(
        widetable[, c(pathwaycol, pathwayidcol)],
        1,
        function(i) paste(i, collapse = "-")
    )
    wt <- as.matrix(widetable[3:dim(widetable)[2]], mode = "numeric")


    # --- Pathway Filtering and Heatmap Visualization [] ---
    # Key functions: mirnaTable
    pathwaySubset <- apply(wt, 1, function(i) length(i[i < 0.2]) > 1)
    wt_sub <- wt[pathwaySubset, ]
    heatmap(
        log2(wt_sub),
        scale = "row",
        cexRow = 0.9,
        margins = c(15, 12)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mirnapath_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mirnapath_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mirnapath_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIRNAPATH:", paste0("    mirnapath: ", packageVersion("miRNApath"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirnapath_results.csv
    touch ${prefix}_mirnapath_output.rds
    echo "BIOC_MIRNAPATH:" > versions.yml
    echo "    mirnapath: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIRNAPATH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIRNAPATH(ch_input)

    emit:
    results  = BIOC_MIRNAPATH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIRNAPATH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIRNAPATH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIRNAPATH.out.versions  // channel: path(versions.yml)
}
