#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: spqn
// The spqn package implements spatial quantile normalization (SpQN). This method was developed to remo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/spqn/inst/doc/spqn.R
// Upstream  : SummarizedExperiment, spqnData
// Downstream: none
//
// Install: BiocManager::install("spqn")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPQN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spqn"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spqn:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spqn:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spqn_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spqn_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spqn_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(spqn)
    library(jsonlite)

    # --- cor m [] ---
    # Key functions: rowData
    data(gtex.4k)
    cor_m <- cor(t(assay(gtex.4k)))
    ave_logrpkm <- rowData(gtex.4k)$ave_logrpkm
    # --- col Sums [] ---
    # Key functions: colSums, sweep, rowMeans, assays, rowData
    gtex <- gtex[rowData(gtex)$gene_type %in%
    c("lincRNA", "protein_coding"), ]
    cSums <- colSums(assay(gtex))
    # --- normalize_correlation [] ---
    # Key functions: normalize_correlation
    cor_m_spqn <- normalize_correlation(cor_m, ave_exp=ave_logrpkm, ngrp=20, size_grp=300, ref_grp=18)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spqn_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spqn_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spqn_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPQN:", paste0("    spqn: ", packageVersion("spqn"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spqn_results.csv
    touch ${prefix}_spqn_output.rds
    echo "BIOC_SPQN:" > versions.yml
    echo "    spqn: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPQN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPQN(ch_input)

    emit:
    results  = BIOC_SPQN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPQN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPQN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPQN.out.versions  // channel: path(versions.yml)
}
