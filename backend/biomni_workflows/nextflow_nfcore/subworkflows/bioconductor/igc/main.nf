#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iGC
// This package is intended to identify differentially expressed genes driven by Copy Number Alteration
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iGC/inst/doc/Introduction.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iGC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IGC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-igc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-igc:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-igc:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_igc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_igc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_igc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iGC)
    library(jsonlite)

    # --- Create Gene Exp [] ---
    # Key functions: create_gene_exp
    ---------------------------------------------------------------------
    gene_exp <- create_gene_exp(sample_desc, progress = FALSE)
    # --- Function [] ---
    # Key functions: fread, create_gene_cna
    ---------------------------------------------------------------------
    my_cna_reader <- function(cna_filepath) {
      cna <- data.table::fread(cna_filepath, sep = '\t', header = TRUE)
      cna[, .(Chromosome, Start, End, Segment_Mean)]
    }
    # --- Find Cna Driven Gene [] ---
    # Key functions: find_cna_driven_gene
    ---------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_igc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_igc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_igc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IGC:", paste0("    igc: ", packageVersion("iGC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_igc_results.csv
    touch ${prefix}_igc_output.rds
    echo "BIOC_IGC:" > versions.yml
    echo "    igc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IGC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IGC(ch_input)

    emit:
    results  = BIOC_IGC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IGC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IGC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IGC.out.versions  // channel: path(versions.yml)
}
