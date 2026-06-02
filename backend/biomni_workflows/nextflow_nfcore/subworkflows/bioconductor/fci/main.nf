#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fCI
// (f-divergence Cutoff Index), is to find DEGs in the transcriptomic & proteomic data, and identify DE
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/fCI/inst/doc/fCI.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("fCI")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FCI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fci"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fci:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fci:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fci_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fci_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fci_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(fCI)
    library(jsonlite)

    # --- Target Identification [] ---
    # Key functions: NPCI, find.fci.targets, setfCI
    fci_obj <- new("NPCI")
    fci_obj <- setfCI(
        fci_obj, 
        7:8, 
        11:12, 
        seq(from = 1.1, to = 3, by = 0.1), 
        TRUE
    )
    targets <- find.fci.targets(fci_obj, c(1, 2, 3), c(4, 5, 6), norm_trim)


    # --- Differential Expression Calling [] ---
    # Key functions: fCI.call.by.index, show.targets
    diff_expr_genes <- show.targets(targets)
    diff_expr_index <- fCI.call.by.index(c(1, 2, 3), c(4, 5, 6), norm_trim)


    # --- Visualization [] ---
    # Key functions: figures
    figures(targets)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fci_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fci_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fci_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FCI:", paste0("    fci: ", packageVersion("fCI"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fci_results.csv
    touch ${prefix}_fci_output.rds
    echo "BIOC_FCI:" > versions.yml
    echo "    fci: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FCI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FCI(ch_input)

    emit:
    results  = BIOC_FCI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FCI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FCI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FCI.out.versions  // channel: path(versions.yml)
}
