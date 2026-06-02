#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: doubletrouble
// doubletrouble aims to identify duplicated genes from whole-genome protein sequences and classify the
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/doubletrouble/inst/doc/doubletrouble_vignette.R
// Upstream  : syntenet, txdbmaker
// Downstream: none
//
// Install: BiocManager::install("doubletrouble")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DOUBLETROUBLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-doubletrouble"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-doubletrouble:1.6.1--r44_0' :
        'quay.io/biocontainers/bioconductor-doubletrouble:1.6.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_doubletrouble_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_doubletrouble_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_doubletrouble_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(doubletrouble)
    library(jsonlite)

    # --- valid [] ---
    # Key functions: valid
    if(!requireNamespace("BiocManager", quietly = TRUE)) {
    install.packages("BiocManager")
    BiocManager::install("doubletrouble")
    # --- process_input [] ---
    # Key functions: process_input
    library(syntenet)
    pdata <- process_input(yeast_seq, yeast_annot)
    names(pdata)
    # --- run diamond intraspecies [] ---
    # Key functions: run_diamond
    data(diamond_intra)
    if(diamond_is_installed()) {
    diamond_intra <- run_diamond(
    # --- binary classification [] ---
    # Key functions: classify_gene_pairs
    c_binary <- classify_gene_pairs(
    names(c_binary)
    head(c_binary$Scerevisiae)
    # --- expanded classification [] ---
    # Key functions: classify_gene_pairs
    c_standard <- classify_gene_pairs(
    names(c_standard)
    head(c_standard$Scerevisiae)
    # --- blast interspecies [] ---
    # Key functions: run_diamond
    data(diamond_inter) # load pre-computed output in case DIAMOND is not installed
    comparisons <- data.frame(
    if(diamond_is_installed()) {
    # --- full classification [] ---
    # Key functions: classify_gene_pairs
    c_extended <- classify_gene_pairs(
    names(c_extended)
    head(c_extended$Scerevisiae)
    # --- classify_genes [] ---
    # Key functions: classify_genes
    c_genes <- classify_genes(c_full)
    names(c_genes)
    head(c_genes$Scerevisiae)
    # --- kaks calculation [] ---
    # Key functions: pairs2kaks
    data(cds_scerevisiae)
    head(cds_scerevisiae)
    cds_list <- list(Scerevisiae = cds_scerevisiae)
    # --- plot_ks_distro [] ---
    # Key functions: plot_ks_distro
    data(gmax_ks)
    head(gmax_ks)
    plot_ks_distro(gmax_ks)
    # --- find ks peaks [] ---
    # Key functions: find_ks_peaks, plot_ks_peaks
    peaks <- find_ks_peaks(gmax_ks$Ks, npeaks = c(2, 3), verbose = TRUE)
    names(peaks)
    str(peaks)
    # --- find peaks explicit [] ---
    # Key functions: find_ks_peaks, plot_ks_peaks
    peaks <- find_ks_peaks(gmax_ks$Ks, npeaks = 2, max_ks = 1)
    plot_ks_peaks(peaks)
    # --- split by peak [] ---
    # Key functions: split_pairs_by_peak, duplicates2counts, plot_duplicate_freqs, wrap_plots
    head(gmax_ks)
    pairs_age_group <- split_pairs_by_peak(gmax_ks[, c(1,2,3)], peaks)
    names(pairs_age_group)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_doubletrouble_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_doubletrouble_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_doubletrouble_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DOUBLETROUBLE:", paste0("    doubletrouble: ", packageVersion("doubletrouble"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_doubletrouble_results.csv
    touch ${prefix}_doubletrouble_output.rds
    echo "BIOC_DOUBLETROUBLE:" > versions.yml
    echo "    doubletrouble: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DOUBLETROUBLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DOUBLETROUBLE(ch_input)

    emit:
    results  = BIOC_DOUBLETROUBLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DOUBLETROUBLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DOUBLETROUBLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DOUBLETROUBLE.out.versions  // channel: path(versions.yml)
}
