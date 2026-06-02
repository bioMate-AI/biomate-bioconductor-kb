#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rsubread
// Alignment, quantification and analysis of RNA sequencing data (including both bulk RNA-seq and scRNA
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rsubread/inst/doc/Rsubread.R
// Upstream  : none
// Downstream: ExCluster
//
// Install: BiocManager::install("Rsubread")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSUBREAD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rsubread"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rsubread:2.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rsubread:2.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rsubread_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rsubread_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rsubread_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Rsubread)
    library(jsonlite)

    # --- Read Alignment [] ---
    # Key functions: align
    reads1 <- system.file("extdata", "reads1.txt.gz", package = "Rsubread")
    reads2 <- system.file("extdata", "reads2.txt.gz", package = "Rsubread")
    align.stat <- align(
        index = "reference_index",
        readfile1 = reads1,
        readfile2 = reads2,
        output_file = "alignResultsPE.BAM",
        phredOffset = 64
    )


    # --- Feature Counting [] ---
    # Key functions: featureCounts
    ann <- data.frame(
        GeneID = c("gene1", "gene1", "gene2", "gene2"),
        Chr = "chr_dummy",
        Start = c(100, 1000, 3000, 5000),
        End = c(500, 1800, 4000, 5500),
        Strand = c("+", "+", "-", "-"),
        stringsAsFactors = FALSE
    )
    fc_PE <- featureCounts(
        "alignResultsPE.BAM",
        annot.ext = ann,
        isPairedEnd = TRUE
    )


    # --- Quality Assessment [] ---
    # Key functions: qualityScores, propmapped
    reads <- system.file("extdata", "reads.txt.gz", package = "Rsubread")
    qs <- qualityScores(filename = reads, offset = 64, nreads = 1000)
    pm <- propmapped("alignResultsPE.BAM")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rsubread_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rsubread_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rsubread_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RSUBREAD:", paste0("    rsubread: ", packageVersion("Rsubread"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rsubread_results.csv
    touch ${prefix}_rsubread_output.rds
    echo "BIOC_RSUBREAD:" > versions.yml
    echo "    rsubread: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RSUBREAD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RSUBREAD(ch_input)

    emit:
    results  = BIOC_RSUBREAD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RSUBREAD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RSUBREAD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RSUBREAD.out.versions  // channel: path(versions.yml)
}
