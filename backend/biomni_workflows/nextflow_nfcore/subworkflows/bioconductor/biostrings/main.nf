#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Biostrings
// Memory efficient string containers, string matching algorithms, and other utilities, for fast manipu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Biostrings/inst/doc/MultipleAlignments.R
// Upstream  : affy, affydata, hgu95av2cdf, hgu95av2probe
// Downstream: alabaster.string, altcdfenvs, amplican, Basic4Cseq, BRAIN
//
// Install: BiocManager::install("Biostrings")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOSTRINGS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biostrings"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biostrings:2.74.1--r44_0' :
        'quay.io/biocontainers/bioconductor-biostrings:2.74.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biostrings_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biostrings_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biostrings_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Biostrings)
    library(jsonlite)

    # --- Hierarchical clustering [] ---
    # Key functions: stringDist, hclust, cutree
    sdist <- stringDist(as(autoMasked,"DNAStringSet"), method="hamming")
    clust <- hclust(sdist, method = "single")
    png(file="goodTree.png")
    # --- Nucleotide frequency QC [] ---
    # Key functions: readDNAMultipleAlignment, readAAMultipleAlignment, rowmask, colmask, maskMotif, maskGaps, alphabetFrequency, consensusMatrix
    rowmask(maskTest) <- IRanges(start=1,end=3)
    rowmask(maskTest,append="intersect") <- IRanges(start=2,end=5)
    rowmask(maskTest,append="replace") <- IRanges(start=5,end=8)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biostrings_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biostrings_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biostrings_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOSTRINGS:", paste0("    biostrings: ", packageVersion("Biostrings"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biostrings_results.csv
    touch ${prefix}_biostrings_output.rds
    echo "BIOC_BIOSTRINGS:" > versions.yml
    echo "    biostrings: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOSTRINGS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOSTRINGS(ch_input)

    emit:
    results  = BIOC_BIOSTRINGS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOSTRINGS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOSTRINGS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOSTRINGS.out.versions  // channel: path(versions.yml)
}
