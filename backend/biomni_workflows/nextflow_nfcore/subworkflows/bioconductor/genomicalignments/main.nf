#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicAlignments
// Provides efficient containers for storing and manipulating short genomic alignments (typically obtai
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicAlignments/inst/doc/GenomicAlignmentsIntroduction.R
// Upstream  : BiocManager, GenomicFeatures, Rsamtools, pasillaBamSubset
// Downstream: AllelicImbalance, Basic4Cseq, ChIPexoQual, groHMM, HelloRanges
//
// Install: BiocManager::install("GenomicAlignments")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICALIGNMENTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicalignments"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicalignments:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicalignments:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicalignments_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicalignments_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicalignments_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomicAlignments)
    library(jsonlite)

    # --- Readgalignments [] ---
    # Key functions: readGAlignments
    library(GenomicAlignments)
    aln1_file <- system.file("extdata", "ex1.bam", package="Rsamtools")
    aln1 <- readGAlignments(aln1_file)
    aln1
    length(aln1)
    # --- Accessors [] ---
    # Key functions: seqnames, seqlevels, strand, cigar, qwidth, start, end
    head(seqnames(aln1))
    seqlevels(aln1)
    head(strand(aln1))
    head(cigar(aln1))
    head(qwidth(aln1))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicalignments_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicalignments_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicalignments_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICALIGNMENTS:", paste0("    genomicalignments: ", packageVersion("GenomicAlignments"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicalignments_results.csv
    touch ${prefix}_genomicalignments_output.rds
    echo "BIOC_GENOMICALIGNMENTS:" > versions.yml
    echo "    genomicalignments: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICALIGNMENTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICALIGNMENTS(ch_input)

    emit:
    results  = BIOC_GENOMICALIGNMENTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICALIGNMENTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICALIGNMENTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICALIGNMENTS.out.versions  // channel: path(versions.yml)
}
