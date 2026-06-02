#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PharmacoGx
// Contains a set of functions to perform large-scale analysis of pharmaco-genomic data. These include 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PharmacoGx/inst/doc/CreatingPharmacoSet.R
// Upstream  : Biobase, CoreGx, S4Vectors, SummarizedExperiment, ggplot2
// Downstream: none
//
// Install: BiocManager::install("PharmacoGx")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHARMACOGX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pharmacogx"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pharmacogx:3.10.1--r44_0' :
        'quay.io/biocontainers/bioconductor-pharmacogx:3.10.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pharmacogx_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pharmacogx_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pharmacogx_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PharmacoGx)
    library(jsonlite)


    # --- Knitcitation [] ---
    # Key functions: cleanbib, cite_options, pandoc, lung, breast, prostate, CVCL_0023, CVCL_0031
    library(knitcitations)

    cleanbib()
    cite_options(citation_format = "pandoc")

    ## -----------------------------------------------------------------------------
    sample <- data.frame(
      sampleid = c("A549", "MCF7", "PC3"),
      tissueid = c("lung", "breast", "prostate"),
      cellosaurus.accession = c("CVCL_0023", "CVCL_0031", "CVCL_0035"),
      row.names = c("A549", "MCF7", "PC3"))

    sample

    ## -----------------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pharmacogx_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pharmacogx_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pharmacogx_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHARMACOGX:", paste0("    pharmacogx: ", packageVersion("PharmacoGx"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pharmacogx_results.csv
    touch ${prefix}_pharmacogx_output.rds
    echo "BIOC_PHARMACOGX:" > versions.yml
    echo "    pharmacogx: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHARMACOGX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHARMACOGX(ch_input)

    emit:
    results  = BIOC_PHARMACOGX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHARMACOGX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHARMACOGX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHARMACOGX.out.versions  // channel: path(versions.yml)
}
