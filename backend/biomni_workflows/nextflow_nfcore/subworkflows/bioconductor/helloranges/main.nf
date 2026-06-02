#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HelloRanges
// Translates bedtools command-line invocations to R code calling functions from the Bioconductor *Rang
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HelloRanges/inst/doc/tutorial.R
// Upstream  : HelloRangesData, parallel
// Downstream: none
//
// Install: BiocManager::install("HelloRanges")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HELLORANGES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-helloranges"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-helloranges:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-helloranges:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_helloranges_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_helloranges_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_helloranges_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HelloRanges)
    library(R_bedtools_intersect)
    library(jsonlite)

    # --- Computing Genomic Complement [] ---
    # Key functions: bedtools_complement
    complement_code <- bedtools_complement(
        "-i exons.bed -g hg19.genome"
    )
    complement_ranges <- eval(complement_code)


    # --- Calculating Genome Coverage [] ---
    # Key functions: bedtools_genomecov
    cov_code <- bedtools_genomecov(
        "-i exons.bed -g hg19.genome"
    )
    cov_results <- eval(cov_code)


    # --- Intersecting Genomic Intervals [] ---
    # Key functions: bedtools_intersect
    intersect_code <- bedtools_intersect(
        "-a peaks.bed -b exons.bed -u"
    )
    intersect_ranges <- eval(intersect_code)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_helloranges_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_helloranges_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_helloranges_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HELLORANGES:", paste0("    helloranges: ", packageVersion("HelloRanges"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_helloranges_results.csv
    touch ${prefix}_helloranges_output.rds
    echo "BIOC_HELLORANGES:" > versions.yml
    echo "    helloranges: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HELLORANGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HELLORANGES(ch_input)

    emit:
    results  = BIOC_HELLORANGES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HELLORANGES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HELLORANGES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HELLORANGES.out.versions  // channel: path(versions.yml)
}
