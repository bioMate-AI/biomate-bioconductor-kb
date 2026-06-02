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

    # --- Gene Duplication Classification [] ---
    # Key functions: classify_gene_pairs, classify_genes
    data(diamond_intra)
    c_binary <- doubletrouble::classify_gene_pairs(
        annotation = pdata$annotation,
        blast_list = diamond_intra,
        scheme = "binary"
    )
    c_genes <- doubletrouble::classify_genes(c_binary)


    # --- Evolutionary Rate Calculation [] ---
    # Key functions: pairs2kaks
    data(cds_scerevisiae)
    cds_list <- list(Scerevisiae = cds_scerevisiae)
    td_pairs <- c_binary$Scerevisiae[c_binary$Scerevisiae$type == "SD", ]
    gene_pairs <- list(Scerevisiae = td_pairs[seq(1, min(5, nrow(td_pairs))), ])
    kaks <- doubletrouble::pairs2kaks(gene_pairs, cds_list)


    # --- Peak Detection and Age Classification [] ---
    # Key functions: find_ks_peaks, plot_ks_peaks, split_pairs_by_peak
    data(gmax_ks)
    peaks <- doubletrouble::find_ks_peaks(gmax_ks$Ks, npeaks = 2, max_ks = 1)
    doubletrouble::plot_ks_peaks(peaks)
    pairs_age_group <- doubletrouble::split_pairs_by_peak(
        gmax_ks[, c(1,2,3)],
        peaks
    )

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
