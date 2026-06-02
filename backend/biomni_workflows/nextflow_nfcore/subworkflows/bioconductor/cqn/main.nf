#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cqn
// A normalization tool for RNA-Seq data, implementing the conditional quantile normalization method.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cqn/inst/doc/cqn.R
// Upstream  : edgeR
// Downstream: KnowSeq
//
// Install: BiocManager::install("cqn")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CQN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cqn"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cqn:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cqn:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cqn_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cqn_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cqn_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cqn)
    library(DGEList)
    library(jsonlite)

    # --- Normalisation Diagnostics and Plotting [] ---
    # Key functions: cqnplot
    par(mfrow = c(1, 2))
    cqnplot(cqn.subset, n = 1, xlab = "GC content", lty = 1, ylim = c(1, 7))
    cqnplot(cqn.subset, n = 2, xlab = "length", lty = 1, ylim = c(1, 7))


    # --- Integration with Differential Expression [] ---
    # Key functions: cqn
    d.mont <- edgeR::DGEList(
        counts = montgomery.subset,
        lib.size = sizeFactors.subset,
        group = rep(c("grp1", "grp2"), each = 5),
        genes = uCovar
    )
    d.mont$offset <- cqn.subset$glm.offset
    design <- model.matrix(~ d.mont$sample$group)
    d.mont.cqn <- edgeR::estimateGLMCommonDisp(d.mont, design = design)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cqn_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cqn_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cqn_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CQN:", paste0("    cqn: ", packageVersion("cqn"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cqn_results.csv
    touch ${prefix}_cqn_output.rds
    echo "BIOC_CQN:" > versions.yml
    echo "    cqn: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CQN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CQN(ch_input)

    emit:
    results  = BIOC_CQN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CQN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CQN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CQN.out.versions  // channel: path(versions.yml)
}
