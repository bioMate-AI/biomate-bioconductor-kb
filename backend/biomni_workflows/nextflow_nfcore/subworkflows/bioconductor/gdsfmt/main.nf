#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gdsfmt
// Provides a high-level R interface to CoreArray Genomic Data Structure (GDS) data files. GDS is porta
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gdsfmt/inst/doc/gdsfmt.R
// Upstream  : none
// Downstream: bigmelon, GDSArray, RAIDS, SAIGEgds, SCArray
//
// Install: BiocManager::install("gdsfmt")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDSFMT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gdsfmt"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gdsfmt:1.42.1--r44_0' :
        'quay.io/biocontainers/bioconductor-gdsfmt:1.42.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gdsfmt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gdsfmt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gdsfmt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gdsfmt)
    library(jsonlite)

    # --- Data Writing and Modification [] ---
    # Key functions: write.gdsn, append.gdsn, closefn.gds
    gfile <- gdsfmt::createfn.gds("test.gds")
    n <- gdsfmt::add.gdsn(gfile, "I1", val = matrix(1:15, nrow = 3))
    gdsfmt::write.gdsn(n, rep(0, 5), start = c(2, 1), count = c(1, -1))
    gdsfmt::append.gdsn(n, 16:24)
    gdsfmt::closefn.gds(gfile)


    # --- Data Retrieval [] ---
    # Key functions: openfn.gds, index.gdsn, read.gdsn
    gfile <- gdsfmt::openfn.gds("test.gds")
    n <- gdsfmt::index.gdsn(gfile, "I1")
    val_all <- gdsfmt::read.gdsn(n)
    val_sub <- gdsfmt::read.gdsn(n, start = c(2, 2), count = c(2, 3))
    gdsfmt::closefn.gds(gfile)


    # --- Data Transformation and Application [] ---
    # Key functions: apply.gdsn, openfn.gds, closefn.gds
    gfile <- gdsfmt::openfn.gds("test.gds")
    n2 <- gdsfmt::index.gdsn(gfile, "I1")
    n_t <- gdsfmt::add.gdsn(
        gfile, "transpose", storage = "int", valdim = c(5, 0),
        replace = TRUE
    )
    gdsfmt::apply.gdsn(
        n2, margin = 1, FUN = c, as.is = "gdsnode",
        target.node = n_t
    )
    gdsfmt::closefn.gds(gfile)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gdsfmt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gdsfmt_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gdsfmt_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GDSFMT:", paste0("    gdsfmt: ", packageVersion("gdsfmt"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gdsfmt_results.csv
    touch ${prefix}_gdsfmt_output.rds
    echo "BIOC_GDSFMT:" > versions.yml
    echo "    gdsfmt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GDSFMT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GDSFMT(ch_input)

    emit:
    results  = BIOC_GDSFMT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GDSFMT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GDSFMT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GDSFMT.out.versions  // channel: path(versions.yml)
}
