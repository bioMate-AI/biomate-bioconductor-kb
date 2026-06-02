#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: procoil
// The package allows for predicting whether a coiled coil sequence (amino acid sequence plus heptad re
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/procoil/inst/doc/procoil.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("procoil")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROCOIL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-procoil"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-procoil:2.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-procoil:2.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_procoil_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_procoil_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_procoil_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(procoil)
    library(AAString)
    library(AAStringSet)
    library(jsonlite)

    # --- Single Sequence Prediction [] ---
    # Key functions: predict
    seq_wt <- "MKQLEDKVEELLSKNYHLENEVARLKKLV"
    reg_wt <- "abcdefgabcdefgabcdefgabcdefga"
    pred_wt <- predict(PrOCoilModel, seq_wt, reg_wt)


    # --- Multiple Sequence Prediction [] ---
    # Key functions: predict
    seqs_mut <- c(
        "GCN4wt" = "MKQLEDKVEELLSKNYHLENEVARLKKLV",
        "GCN4_N16Y_L19T" = "MKQLEDKVEELLSKYYHTENEVARLKKLV",
        "GCN4_E22R_K27E" = "MKQLEDKVEELLSKNYHLENRVARLEKLV"
    )
    regs_mut <- rep("abcdefgabcdefgabcdefgabcdefga", 3)
    pred_mut <- predict(PrOCoilModel, seqs_mut, regs_mut)


    # --- Visualization [] ---
    # Key functions: plot, heatmap
    seqs_mut <- c(
        "GCN4wt" = "MKQLEDKVEELLSKNYHLENEVARLKKLV",
        "GCN4_N16Y_L19T" = "MKQLEDKVEELLSKYYHTENEVARLKKLV"
    )
    regs_mut <- rep("abcdefgabcdefgabcdefgabcdefga", 2)
    pred_mut <- predict(PrOCoilModel, seqs_mut, regs_mut)
    plot(pred_mut, legend = c("wild type", "mutant"))
    heatmap(pred_mut)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_procoil_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_procoil_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_procoil_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROCOIL:", paste0("    procoil: ", packageVersion("procoil"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_procoil_results.csv
    touch ${prefix}_procoil_output.rds
    echo "BIOC_PROCOIL:" > versions.yml
    echo "    procoil: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROCOIL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROCOIL(ch_input)

    emit:
    results  = BIOC_PROCOIL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROCOIL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROCOIL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROCOIL.out.versions  // channel: path(versions.yml)
}
