#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: coseq
// Co-expression analysis for expression profiles arising from high-throughput sequencing data. Feature
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/coseq/inst/doc/coseq.R
// Upstream  : Biobase, DESeq2, corrplot, edgeR, ggforce
// Downstream: none
//
// Install: BiocManager::install("coseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-coseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-coseq:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-coseq:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_coseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_coseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_coseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NormMixParam)
    library(jsonlite)

    # --- figure=TRUE [] ---
    # Key functions: compareICL
    compareICL(list(runArcsin, runLogit))
    # --- figure=TRUE [] ---
    # Key functions: compareARI
    compareARI(runArcsin, K=8:12)
    summary(runArcsin)
    # --- figure=TRUE [] ---
    # Key functions: NormMixParam, corrplot, clusters, assay
    rho <- NormMixParam(runArcsin)$rho
    colnames(rho1) <- rownames(rho1) <- paste0(colnames(rho1), "\n", conds)
    corrplot(rho1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_coseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_coseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_coseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COSEQ:", paste0("    coseq: ", packageVersion("coseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_coseq_results.csv
    touch ${prefix}_coseq_output.rds
    echo "BIOC_COSEQ:" > versions.yml
    echo "    coseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COSEQ(ch_input)

    emit:
    results  = BIOC_COSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COSEQ.out.versions  // channel: path(versions.yml)
}
