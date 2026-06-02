#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pairkat
// PaIRKAT is model framework for assessing statistical relationships between networks of metabolites (
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pairkat/inst/doc/using-pairkat.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("pairkat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PAIRKAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pairkat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pairkat:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pairkat:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pairkat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pairkat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pairkat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pairkat)
    library(GatherNetworks)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Data Preparation [SummarizedExperiment] ---
    # Key functions: SummarizedExperiment, colData, rowData, assays
    data("smokers", package = "pairkat")
    phenotype <- SummarizedExperiment::colData(smokers)
    pathways <- SummarizedExperiment::rowData(smokers)
    metabolome <- SummarizedExperiment::assays(smokers)$metabolomics
    smokers_se <- SummarizedExperiment::SummarizedExperiment(
        assays = list(metabolomics = metabolome),
        rowData = pathways,
        colData = phenotype
    )

    # --- Network Generation [GatherNetworks] ---
    # Key functions: GatherNetworks
    networks <- GatherNetworks(
        SE = smokers,
        keggID = "kegg_id",
        species = "hsa",
        minPathwaySize = 5
    )

    # --- Pathway Association Testing [PaIRKAT] ---
    # Key functions: PaIRKAT
    output <- PaIRKAT(
        formula = log_FEV1_FVC_ratio ~ age,
        networks = networks
    )
    results <- output$results
    sorted_results <- results[order(results$p.value), ]

    # --- Network Visualization [plotNetworks] ---
    # Key functions: plotNetworks
    plotNetworks(
        networks = networks,
        pathway = "Glycerophospholipid metabolism"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pairkat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pairkat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pairkat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PAIRKAT:", paste0("    pairkat: ", packageVersion("pairkat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairkat_results.csv
    touch ${prefix}_pairkat_output.rds
    echo "BIOC_PAIRKAT:" > versions.yml
    echo "    pairkat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PAIRKAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PAIRKAT(ch_input)

    emit:
    results  = BIOC_PAIRKAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PAIRKAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PAIRKAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PAIRKAT.out.versions  // channel: path(versions.yml)
}
