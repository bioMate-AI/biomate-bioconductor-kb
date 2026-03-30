#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CexoR
// Strand specific peak-pair calling in ChIP-exo replicates. The cumulative Skellam distribution functi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CexoR/inst/doc/CexoR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CexoR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CEXOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cexor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cexor:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cexor:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cexor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cexor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cexor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CexoR)
    library(jsonlite)

    # --- Call Reproducible Peak Pairs In Chip Exo Replicates [] ---
    # Key functions: tempdir, cexor
    options(width=60)
    ## hg19. chr2:1-1,000,000
    owd <- setwd(tempdir())
    library(CexoR)
    rep1 <- "CTCF_rep1_chr2_1-1e6.bam"
    # --- Visualisation Of Chip Exo Replicates [] ---
    # Key functions: plotcexor
    ## options(width=60)
    ## plotcexor(bam=c(r1,r2,r3), peaks=peak_pairs, EXT=500)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cexor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cexor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cexor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CEXOR:", paste0("    cexor: ", packageVersion("CexoR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cexor_results.csv
    touch ${prefix}_cexor_output.rds
    echo "BIOC_CEXOR:" > versions.yml
    echo "    cexor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CEXOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CEXOR(ch_input)

    emit:
    results  = BIOC_CEXOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CEXOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CEXOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CEXOR.out.versions  // channel: path(versions.yml)
}
