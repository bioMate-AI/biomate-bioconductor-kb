#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rCGH
// A comprehensive pipeline for analyzing and interactively visualizing genomic profiles generated thro
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rCGH/inst/doc/rCGH.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rCGH")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCGH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcgh"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rcgh:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rcgh:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcgh_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcgh_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcgh_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EMnormalize)
    library(jsonlite)

    # --- read Affy Cyto Scan [] ---
    # Key functions: readAffyCytoScan
    library(rCGH)
    filePath <- system.file("extdata",
    cgh <- readAffyCytoScan(filePath, sampleName = "CSc-Example",
    # --- set Info [] ---
    # Key functions: setInfo
    setInfo(cgh, "item1") <- 35
    setInfo(cgh, "item2") <- TRUE
    setInfo(cgh, "item3") <- "someComment"
    # --- get Info [] ---
    # Key functions: getInfo
    getInfo(cgh)
    getInfo(cgh, c("item1", "item3"))
    # --- adjust Signal [] ---
    # Key functions: adjustSignal
    cgh <- adjustSignal(cgh, nCores=1)
    # --- segment C G H [] ---
    # Key functions: segmentCGH, getSegTable
    cgh <- segmentCGH(cgh, nCores=1)
    segTable <- getSegTable(cgh)
    # --- E Mnormalize [] ---
    # Key functions: EMnormalize
    cgh <- EMnormalize(cgh)
    # --- by Gene Table [] ---
    # Key functions: byGeneTable
    geneTable <- byGeneTable(segTable)
    head(geneTable, n=3)
    # --- multiplot [] ---
    # Key functions: multiplot
    multiplot(cgh, symbol = c("egfr", "erbb2"))
    # --- recenter [] ---
    # Key functions: recenter, plotProfile
    recenter(cgh) <- 2
    plotProfile(cgh, symbol = c("egfr", "erbb2"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rcgh_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rcgh_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rcgh_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCGH:", paste0("    rcgh: ", packageVersion("rCGH"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcgh_results.csv
    touch ${prefix}_rcgh_output.rds
    echo "BIOC_RCGH:" > versions.yml
    echo "    rcgh: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCGH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCGH(ch_input)

    emit:
    results  = BIOC_RCGH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCGH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCGH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCGH.out.versions  // channel: path(versions.yml)
}
