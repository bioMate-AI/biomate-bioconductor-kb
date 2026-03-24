#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rhinotypeR
// "rhinotypeR" is designed to automate the comparison of sequence data against prototype strains, stre
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rhinotypeR/inst/doc/rhinotypeR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rhinotypeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RHINOTYPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rhinotyper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rhinotyper:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rhinotyper:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rhinotyper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rhinotyper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rhinotyper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SNPeek)
    library(jsonlite)

    # --- Readdnastringset [] ---
    # Key functions: readDNAStringSet
    ---------------------------------------------------------------------
    sequences <- Biostrings::readDNAStringSet(system.file("extdata", "input_aln.fasta", package="rhinotypeR"))
    # --- Snpeek [] ---
    # Key functions: SNPeek
    ---------------------------------------------------------------------
    SNPeek(sequences)
    # --- Pairwisedistances [] ---
    # Key functions: pairwiseDistances
    ---------------------------------------------------------------------
    distances <- pairwiseDistances(sequences, model = "p-distance", gapDeletion = TRUE)
    # --- Assigntypes [] ---
    # Key functions: assignTypes
    ---------------------------------------------------------------------
    genotypes <- assignTypes(sequences, model = "p-distance", gapDeletion = TRUE, threshold = 0.105)
    head(genotypes)
    # --- Plotfrequency [] ---
    # Key functions: plotFrequency
    ---------------------------------------------------------------------
    plotFrequency(genotypes)
    # --- Plotdistances [] ---
    # Key functions: plotDistances
    ---------------------------------------------------------------------
    plotDistances(distances)
    # --- Plottree [] ---
    # Key functions: plotTree
    ---------------------------------------------------------------------
    # sub-sample
    sampled_distances <- distances[1:30,1:30]
    plotTree(sampled_distances, hang = -1, cex = 0.6, main = "A simple tree", xlab = "", ylab = "Genetic distance")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rhinotyper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rhinotyper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rhinotyper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RHINOTYPER:", paste0("    rhinotyper: ", packageVersion("rhinotypeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rhinotyper_results.csv
    touch ${prefix}_rhinotyper_output.rds
    echo "BIOC_RHINOTYPER:" > versions.yml
    echo "    rhinotyper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RHINOTYPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RHINOTYPER(ch_input)

    emit:
    results  = BIOC_RHINOTYPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RHINOTYPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RHINOTYPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RHINOTYPER.out.versions  // channel: path(versions.yml)
}
