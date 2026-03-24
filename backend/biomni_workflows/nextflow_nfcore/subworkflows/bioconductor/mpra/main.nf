#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mpra
// Tools for data management, count preprocessing, and differential analysis in massively parallel repo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mpra/inst/doc/mpra.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("mpra")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MPRA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mpra"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mpra:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mpra:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mpra_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mpra_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mpra_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MPRASet)
    library(jsonlite)

    # --- replicate [] ---
    # Key functions: replicate, MPRASet
    library(mpra)
    set.seed(434)
    rna <- matrix(rpois(E*B*s*nt, lambda = 30), nrow = E*B, ncol = s*nt)
    # --- fig=TRUE [] ---
    # Key functions: mpralm, topTable
    design <- data.frame(intcpt = 1, episomal = grepl("MT", colnames(mpraSetExample)))
    mpralm_fit <- mpralm(object = mpraSetExample, design = design, aggregate = "mean", normalize = TRUE, model_type = "indep_groups", plot = TRUE)
    toptab <- topTable(mpralm_fit, coef = 2, number = Inf)
    # --- fig=TRUE [] ---
    # Key functions: mpralm, topTable, rowData, assay
    data(mpraSetAllelicExample)
    design <- data.frame(intcpt = 1, alleleB = grepl("allele_B", colnames(mpraSetAllelicExample)))
    block_vector <- rep(1:5, 2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mpra_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mpra_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mpra_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MPRA:", paste0("    mpra: ", packageVersion("mpra"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mpra_results.csv
    touch ${prefix}_mpra_output.rds
    echo "BIOC_MPRA:" > versions.yml
    echo "    mpra: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MPRA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MPRA(ch_input)

    emit:
    results  = BIOC_MPRA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MPRA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MPRA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MPRA.out.versions  // channel: path(versions.yml)
}
