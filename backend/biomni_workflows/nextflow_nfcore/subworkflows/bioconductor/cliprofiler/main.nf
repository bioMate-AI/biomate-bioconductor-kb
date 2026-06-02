#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cliProfiler
// An easy and fast way to visualize and profile the high-throughput IP data. This package generates th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cliProfiler/inst/doc/cliProfilerIntroduction.R
// Upstream  : BiocManager, ggplot2, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("cliProfiler")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLIPROFILER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cliprofiler"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cliprofiler:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cliprofiler:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cliprofiler_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cliprofiler_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cliprofiler_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cliProfiler)
    library(jsonlite)


    # --- Initialize [] ---
    # Key functions: readRDS, import.gff3, extdata, cliProfiler, test.rds, annotation_test.gff3
    library(cliProfiler)

    ## -----------------------------------------------------------------------------
    testpath <- system.file("extdata", package = "cliProfiler")
    ## loading the test GRanges object
    test <- readRDS(file.path(testpath, "test.rds"))
    ## Show an example of GRanges object
    test

    ## -----------------------------------------------------------------------------
    ## the path for the test gff3 file
    test_gff3 <- file.path(testpath, "annotation_test.gff3")
    ## the gff3 file can be loaded by import.gff3 function in rtracklayer package
    shown_gff3 <- rtracklayer::import.gff3(test_gff3)
    ## show the test gff3 file

    # --- Eval=false [] ---
    # Key functions: metaGeneProfile, intronProfile
    #  metaGeneProfile(object = test, annotation = test_gff3, exlevel = 3,
    #                  extranscript_support_level = c(4,5,6))

    ## -----------------------------------------------------------------------------
    meta <- metaGeneProfile(object = test, annotation = test_gff3, split = TRUE)
    meta[[2]]

    ## -----------------------------------------------------------------------------
    intron <-  intronProfile(test, test_gff3)

    ## -----------------------------------------------------------------------------
    intron[[1]]

    ## -----------------------------------------------------------------------------
    intron[[2]]

    # --- Results='hide' [] ---
    # Key functions: import.gff3, windowProfile, exon
    library(rtracklayer)
    ## Extract all the exon annotation
    test_anno <- rtracklayer::import.gff3(test_gff3)
    test_anno <- test_anno[test_anno$type == "exon"]
    ## Run the windowProfile
    window_profile <- windowProfile(test, test_anno)

    ## -----------------------------------------------------------------------------
    window_profile[[1]]

    ## -----------------------------------------------------------------------------
    window_profile[[2]]

    ## -----------------------------------------------------------------------------
    ## Example for running the motifProfile

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cliprofiler_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cliprofiler_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cliprofiler_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLIPROFILER:", paste0("    cliprofiler: ", packageVersion("cliProfiler"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cliprofiler_results.csv
    touch ${prefix}_cliprofiler_output.rds
    echo "BIOC_CLIPROFILER:" > versions.yml
    echo "    cliprofiler: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLIPROFILER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLIPROFILER(ch_input)

    emit:
    results  = BIOC_CLIPROFILER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLIPROFILER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLIPROFILER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLIPROFILER.out.versions  // channel: path(versions.yml)
}
