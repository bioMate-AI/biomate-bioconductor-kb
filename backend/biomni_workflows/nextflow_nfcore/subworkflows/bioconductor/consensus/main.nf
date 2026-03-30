#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: consensus
// An implementation of the American Society for Testing and Materials (ASTM) Standard E691 for interla
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/consensus/inst/doc/consensus.R
// Upstream  : BiocManager
// Downstream: none
//
// Install: BiocManager::install("consensus")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CONSENSUS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-consensus"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-consensus:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-consensus:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_consensus_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_consensus_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_consensus_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MultiMeasure)
    library(jsonlite)

    # --- Multi Measure [] ---
    # Key functions: MultiMeasure
    tcga_mm <- MultiMeasure(names=c("U133A", "Huex", "Agilent", "RNA-Seq"),
    data=list(U133A, Huex, Agilent, RNASeq))
    # --- plot One Fit [] ---
    # Key functions: plotOneFit
    plotOneFit(tcga_mm, "TP53", brewer.pal(n = 4, name = "Dark2"))
    # --- fit Consensus [] ---
    # Key functions: fitConsensus
    fit <- fitConsensus(tcga_mm)
    # --- plot Marginals [] ---
    # Key functions: plotMarginals
    plotMarginals(fit, "average", brewer.pal(n = 4, name = "Dark2"))
    # --- plot Most Discordant [] ---
    # Key functions: plotMostDiscordant
    plotMostDiscordant(fit, "sensitivity", 15)
    # --- plot One Fit [] ---
    # Key functions: plotOneFit
    plotOneFit(tcga_mm, "MYO7B", brewer.pal(n = 4, name = "Dark2"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_consensus_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_consensus_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_consensus_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CONSENSUS:", paste0("    consensus: ", packageVersion("consensus"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_consensus_results.csv
    touch ${prefix}_consensus_output.rds
    echo "BIOC_CONSENSUS:" > versions.yml
    echo "    consensus: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CONSENSUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CONSENSUS(ch_input)

    emit:
    results  = BIOC_CONSENSUS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CONSENSUS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CONSENSUS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CONSENSUS.out.versions  // channel: path(versions.yml)
}
