#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DECIPHER
// A toolset for deciphering and managing biological sequences.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DECIPHER/inst/doc/ArtOfAlignmentInR.R
// Upstream  : none
// Downstream: AssessORF, sangeranalyseR, SynExtend
//
// Install: BiocManager::install("DECIPHER")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECIPHER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-decipher"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-decipher:3.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-decipher:3.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_decipher_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_decipher_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_decipher_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DECIPHER)
    library(AdjustAlignment)
    library(AlignDB)
    library(AlignProfiles)
    library(AlignSeqs)
    library(AlignSynteny)
    library(AlignTranslation)
    library(BrowseDB)
    library(BrowseSeqs)
    library(FindSynteny)
    library(RNAStringSet)
    library(jsonlite)

    # --- Multiple Sequence Alignment [] ---
    # Key functions: AlignSeqs
    aligned_dna <- AlignSeqs(
        dna_oriented,
        guideTree = NULL,
        gapOpening = -18,
        gapExtension = -2,
        verbose = FALSE
    )


    # --- Distance Matrix Computation [] ---
    # Key functions: DistanceMatrix
    dist_matrix <- DistanceMatrix(
        aligned_dna,
        correction = "Jukes-Cantor",
        processors = 1,
        verbose = FALSE
    )


    # --- Sequence Clustering and Tree Construction [] ---
    # Key functions: IdClusters, TreeLine
    clusters <- IdClusters(
        dist_matrix,
        method = "NJ",
        cutoff = 0.05,
        processors = 1,
        verbose = FALSE
    )
    tree <- TreeLine(
        myDistMatrix = dist_matrix,
        method = "NJ",
        showPlot = FALSE,
        verbose = FALSE
    )


    # --- Alignment Visualization and Export [] ---
    # Key functions: BrowseSeqs, writeXStringSet
    BrowseSeqs(
        aligned_dna,
        htmlFile = "aligned_sequences.html",
        openURL = FALSE
    )
    writeXStringSet(
        aligned_dna,
        filepath = "aligned_sequences.fasta"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_decipher_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_decipher_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_decipher_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DECIPHER:", paste0("    decipher: ", packageVersion("DECIPHER"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_decipher_results.csv
    touch ${prefix}_decipher_output.rds
    echo "BIOC_DECIPHER:" > versions.yml
    echo "    decipher: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DECIPHER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DECIPHER(ch_input)

    emit:
    results  = BIOC_DECIPHER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DECIPHER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DECIPHER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DECIPHER.out.versions  // channel: path(versions.yml)
}
