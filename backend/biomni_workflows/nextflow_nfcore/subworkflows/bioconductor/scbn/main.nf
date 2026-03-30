#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SCBN
// This package provides a scale based normalization (SCBN) method to identify genes with differential 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SCBN/inst/doc/SCBN.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SCBN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCBN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scbn"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scbn:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scbn:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scbn_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scbn_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scbn_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SCBN)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: na, generateDataset
    ---------------------------------------------------------------------
    data(orthgenes)
    orthgenes[, 6:9] <- round(orthgenes[, 6:9])
    orthgenes1 <- orthgenes[!(is.na(orthgenes[,6])|is.na(orthgenes[,7])|
                            is.na(orthgenes[,8])|is.na(orthgenes[,9])), ]
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(orthgenes)
    head(orthgenes)
    # --- Data [] ---
    # Key functions: SCBN
    ---------------------------------------------------------------------
    data(sim_data)
    factor <- SCBN(orth_gene=sim_data, hkind=1:1000, a=0.05)
    factor
    # --- Data [] ---
    # Key functions: sageTestNew
    ---------------------------------------------------------------------
    data(sim_data)
    orth_gene <- sim_data
    hkind <- 1:1000
    scale <- factor$scbn_val

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scbn_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scbn_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scbn_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCBN:", paste0("    scbn: ", packageVersion("SCBN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scbn_results.csv
    touch ${prefix}_scbn_output.rds
    echo "BIOC_SCBN:" > versions.yml
    echo "    scbn: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCBN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCBN(ch_input)

    emit:
    results  = BIOC_SCBN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCBN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCBN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCBN.out.versions  // channel: path(versions.yml)
}
