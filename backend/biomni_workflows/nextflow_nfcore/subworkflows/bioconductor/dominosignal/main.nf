#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dominoSignal
// dominoSignal is a package developed to analyze cell signaling through ligand - receptor - transcript
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dominoSignal/inst/doc/dominoSignal.R
// Upstream  : ComplexHeatmap, SingleCellExperiment, circlize, knitr, plyr
// Downstream: none
//
// Install: BiocManager::install("dominoSignal")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DOMINOSIGNAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dominosignal"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dominosignal:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dominosignal:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dominosignal_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dominosignal_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dominosignal_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocFileCache)
    library(jsonlite)

    # --- Load saved R data object [] ---
    # Key functions: BiocFileCache, bfcrpath, untar
    bfc <- BiocFileCache::BiocFileCache(ask = FALSE)
    pbmc_url <- paste0(data_url, "/pbmc3k_sce.rds")
    pbmc <- BiocFileCache::bfcrpath(bfc, pbmc_url)
    # --- Create Regulon List [] ---
    # Key functions: create_regulon_list_scenic
    colnames(regulons) <- c(
    regulon_list <- create_regulon_list_scenic(regulons = regulons)
    # --- Load CellPhoneDB Database [] ---
    # Key functions: create_rl_map_cellphonedb
    complexes <- read.csv(
    paste0(
    genes <- read.csv(
    # --- Appending interactions [] ---
    # Key functions: rbind, kable
    col_int_df <- data.frame(
    rl_map_append <- rbind(col_int_df, rl_map)
    knitr::kable(head(rl_map_append))
    # --- Create Domino [] ---
    # Key functions: create_domino
    pbmc_dom <- create_domino(
    features: TF activation scores (AUC matrix)
    # --- Build Domino [] ---
    # Key functions: build_domino
    pbmc_dom <- build_domino(
    # --- Build Domino All Significant Interactions [] ---
    # Key functions: build_domino, feat_heatmap, signaling_network, gene_network
    pbmc_dom_all <- build_domino(
    feat_heatmap(pbmc_dom,
    row_names_gp = grid::gpar(fontsize = 4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dominosignal_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dominosignal_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dominosignal_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DOMINOSIGNAL:", paste0("    dominosignal: ", packageVersion("dominoSignal"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dominosignal_results.csv
    touch ${prefix}_dominosignal_output.rds
    echo "BIOC_DOMINOSIGNAL:" > versions.yml
    echo "    dominosignal: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DOMINOSIGNAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DOMINOSIGNAL(ch_input)

    emit:
    results  = BIOC_DOMINOSIGNAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DOMINOSIGNAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DOMINOSIGNAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DOMINOSIGNAL.out.versions  // channel: path(versions.yml)
}
