#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TSCAN
// Provides methods to perform trajectory analysis based on a minimum spanning tree constructed from cl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TSCAN/inst/doc/TSCAN.R
// Upstream  : none
// Downstream: OSCA.advanced, OSCA.multisample
//
// Install: BiocManager::install("TSCAN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TSCAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tscan"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tscan:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tscan:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tscan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tscan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tscan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TSCANorder)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: preprocess
    ---------------------------------------------------------------------
    library(TSCAN)
    data(lpsdata)
    procdata <- preprocess(lpsdata)
    # --- Exprmclust [] ---
    # Key functions: exprmclust
    ---------------------------------------------------------------------
    lpsmclust <- exprmclust(procdata)
    # --- Plotmclust [] ---
    # Key functions: plotmclust
    ---------------------------------------------------------------------
    plotmclust(lpsmclust)
    # --- Tscanorder [] ---
    # Key functions: TSCANorder
    ---------------------------------------------------------------------
    lpsorder <- TSCANorder(lpsmclust)
    lpsorder
    # --- Difftest [] ---
    # Key functions: difftest
    ---------------------------------------------------------------------
    diffval <- difftest(procdata,lpsorder)
    #Selected differentially expressed genes under qvlue cutoff of 0.05
    head(row.names(diffval)[diffval$qval < 0.05])
    # --- Log2 [] ---
    # Key functions: singlegeneplot, TSCANorder
    ---------------------------------------------------------------------
    STAT2expr <- log2(lpsdata["STAT2",]+1)
    singlegeneplot(STAT2expr, TSCANorder(lpsmclust,flip=TRUE,orderonly=FALSE))
    # --- Frame [] ---
    # Key functions: frame, ifelse, TSCANorder
    ---------------------------------------------------------------------
    subpopulation <- data.frame(cell = colnames(procdata), sub = ifelse(grepl("Unstimulated",colnames(procdata)),0,1), stringsAsFactors = FALSE)
    #Comparing ordering with or without marker gene information
    order1 <- TSCANorder(lpsmclust)
    order2 <- TSCANorder(lpsmclust, c(1,2,3))
    # --- Orderscore [] ---
    # Key functions: orderscore
    ---------------------------------------------------------------------
    orderscore(subpopulation, orders)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tscan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tscan_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tscan_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TSCAN:", paste0("    tscan: ", packageVersion("TSCAN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tscan_results.csv
    touch ${prefix}_tscan_output.rds
    echo "BIOC_TSCAN:" > versions.yml
    echo "    tscan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TSCAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TSCAN(ch_input)

    emit:
    results  = BIOC_TSCAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TSCAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TSCAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TSCAN.out.versions  // channel: path(versions.yml)
}
