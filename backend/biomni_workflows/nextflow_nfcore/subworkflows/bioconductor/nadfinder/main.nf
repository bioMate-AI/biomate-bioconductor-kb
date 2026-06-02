#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NADfinder
// Nucleolus is an important structure inside the nucleus in eukaryotic cells. It is the site for trans
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NADfinder/inst/doc/NADfinder.R
// Upstream  : SummarizedExperiment, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("NADfinder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NADFINDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nadfinder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nadfinder:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nadfinder:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nadfinder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nadfinder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nadfinder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NADfinder)
    library(jsonlite)


    # --- Quick Start [] ---
    # Key functions: dir, extdata
    ## load the library
    library(NADfinder)
    library(SummarizedExperiment)
    ## test bam files in the package
    path <- system.file("extdata", package = "NADfinder", lib.loc = NULL,
                mustWork = TRUE)
    bamFiles <- dir(path, ".bam$")

    ## window size for tile of genome. Here we set it to a big window size,
    ## ie., 50k because of the following two reasons:
    ## 1. peaks of NADs are wide;
    ## 2. data will be smoothed better with bigger window size.
    ws <- 50000
    ## step for tile of genome
    step <- 5000

    # --- Eval=false [] ---
    # Key functions: tileCount, log2se
    #  se <- tileCount(reads=file.path(path, bamFiles),
    #                  genome=Mmusculus,
    #                  windowSize=ws,
    #                  step=step,
    #                  mode = IntersectionNotStrict,
    #                  dataOverSamples = FALSE)

    ## -----------------------------------------------------------------------------
    data(single.count)
    se <- single.count

    ## -----------------------------------------------------------------------------

    ## Calculate ratios for peak calling. We use nucleoleus vs genomic DNA.
    # --- Eval=false [] ---
    # Key functions: tileCount, log2se
    #  se <- tileCount(reads=file.path(path, f),
    #                  genome=Mmusculus,
    #                  windowSize=ws,
    #                  step=step)

    ## -----------------------------------------------------------------------------
    data(triplicate.count)
    se <- triplicate.count

    ## Calculate ratios for nucleoloar vs genomic samples.

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nadfinder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nadfinder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nadfinder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NADFINDER:", paste0("    nadfinder: ", packageVersion("NADfinder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nadfinder_results.csv
    touch ${prefix}_nadfinder_output.rds
    echo "BIOC_NADFINDER:" > versions.yml
    echo "    nadfinder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NADFINDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NADFINDER(ch_input)

    emit:
    results  = BIOC_NADFINDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NADFINDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NADFINDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NADFINDER.out.versions  // channel: path(versions.yml)
}
