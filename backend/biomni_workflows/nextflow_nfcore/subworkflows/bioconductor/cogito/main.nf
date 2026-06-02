#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Cogito
// Biological studies often consist of multiple conditions which are examined with different laboratory
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Cogito/inst/doc/Cogito.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Cogito")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COGITO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cogito"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cogito:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cogito:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cogito_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cogito_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cogito_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Cogito)
    library(jsonlite)


    # --- Murine Example Data Set Rna [] ---
    # Key functions: cogito
    head(MurEpi.RNA.small[, 1:3])

    # --- Murine Example Data Set Rrbs [] ---
    # Key functions: cogito
    head(MurEpi.RRBS.small[, 1:3])

    # --- Murine Example Data Set Ch Ip [] ---
    # Key functions: cogito
    head(MurEpi.ChIP.small[[1]])

    # --- Workflow Aggregate Ranges With Small Murine Data Set [] ---
    # Key functions: aggregateRanges, murine.example
    mm9 <- TxDb.Mmusculus.UCSC.mm9.knownGene::TxDb.Mmusculus.UCSC.mm9.knownGene

    example.dataset <- list(ChIP = MurEpi.ChIP.small, 
                            RNA = MurEpi.RNA.small,
                            RRBS = MurEpi.RRBS.small)

    aggregated.ranges <- aggregateRanges(ranges = example.dataset,
                                            organism = mm9,
                                            name = "murine.example")

    # --- Workflow Result Genes Of Aggregate Ranges With Small Murine Data Set [] ---
    # Key functions: cogito
    head(aggregated.ranges$genes[, c(1, 2:3, 13:14, 27:28)])

    # --- Workflow Result 1 Genes Of Aggregate Ranges With Small Murine Data Set [] ---
    # Key functions: cogito
    lapply(aggregated.ranges$config$technologies, head, 3)
    head(lapply(aggregated.ranges$config$conditions, head, 3), 3)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cogito_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cogito_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cogito_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COGITO:", paste0("    cogito: ", packageVersion("Cogito"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cogito_results.csv
    touch ${prefix}_cogito_output.rds
    echo "BIOC_COGITO:" > versions.yml
    echo "    cogito: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COGITO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COGITO(ch_input)

    emit:
    results  = BIOC_COGITO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COGITO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COGITO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COGITO.out.versions  // channel: path(versions.yml)
}
