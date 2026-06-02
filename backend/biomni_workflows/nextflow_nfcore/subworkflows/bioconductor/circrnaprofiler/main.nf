#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: circRNAprofiler
// R-based computational framework for a comprehensive in silico analysis of circRNAs. This computation
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/circRNAprofiler/inst/doc/circRNAprofiler.R
// Upstream  : VennDiagram, ggplot2, ggpubr, gridExtra, knitr
// Downstream: none
//
// Install: BiocManager::install("circRNAprofiler")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CIRCRNAPROFILER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-circrnaprofiler"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-circrnaprofiler:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-circrnaprofiler:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_circrnaprofiler_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_circrnaprofiler_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_circrnaprofiler_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(circRNAprofiler)
    library(jsonlite)


    # --- Global Options [] ---
    # Key functions: set, source, render_toc.R
    library(knitr)
    knitr::opts_chunk$set(fig.path='figs/', warning=FALSE, message=FALSE, collapse=TRUE)
    source("render_toc.R")

    # --- Toc [] ---
    # Key functions: render_toc, circRNAprofiler.Rmd
    render_toc("circRNAprofiler.Rmd")

    # --- Eval = False [] ---
    # Key functions: checkProjectFolder, formatGTF, gencode.V19.annotation.gtf, gtf
    #  # Set project folder projectCirc as your working directory and run:
    #  check <- checkProjectFolder()
    #  check

    ## -----------------------------------------------------------------------------
    # Set project folder projectCirc as your working directory.
    # Download gencode.V19.annotation.gtf from https://www.gencodegenes.org/ and 
    # put it in the working directory, then run:
    # gtf <- formatGTF("gencode.V19.annotation.gtf")

    # For example purpose load a short version of the formatted gtf file generated
    # using the command above.
    data("gtf")
    head(gtf)


    # --- Eval = False [] ---
    # Key functions: liftBSJcoords, transcripts.txt, annotateBSJs, hg19ToMm9
    #  liftedBSJcoords <- liftBSJcoords(filteredCirc, map = "hg19ToMm9",
    #                                   annotationHubID = "AH14155")

    ## -----------------------------------------------------------------------------
    # If you want to analysis specific transcripts report them in transcripts.txt (optional).
    # If transcripts.txt is not present in your working directory specify pathToTranscripts.
    # As default transcripts.txt is searched in the wd.

    # As an example of the 1458 filtered circRNAs we annotate only the firt 30 
    # circRNAs
    annotatedBSJs <- annotateBSJs(filteredCirc[1:30,], gtf, isRandom = FALSE) 
    head(annotatedBSJs)

    ## -----------------------------------------------------------------------------
    # First find frequency of single exon circRNAs

    # --- Eval = False [] ---
    # Key functions: requireNamespace, install
    #  # Select ALPK2:-:chr18:56247780:56246046 circRNA
    #  annotatedCirc <-
    #  annotatedBSJs[annotatedBSJs$id == "ALPK2:-:chr18:56247780:56246046", ]
    #  
    #  # As background data set we used all the remaining 1457 filered circRNAs.
    #  # Alternatively the subset of randomly generated back-spliced junctions can be used.
    #  annotatedBackgroundCircs <-
    #  annotatedBSJs[which(annotatedBSJs$id != "ALPK2:-:chr18:56247780:56246046"), ]

    ## -----------------------------------------------------------------------------
    # All the sequences will be retrieved from the BSgenome package which contains 
    # the serquences of the genome of interest
    if (!requireNamespace("BSgenome.Hsapiens.UCSC.hg19", quietly = TRUE)){
      BiocManager::install("BSgenome.Hsapiens.UCSC.hg19")
    }

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_circrnaprofiler_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_circrnaprofiler_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_circrnaprofiler_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CIRCRNAPROFILER:", paste0("    circrnaprofiler: ", packageVersion("circRNAprofiler"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_circrnaprofiler_results.csv
    touch ${prefix}_circrnaprofiler_output.rds
    echo "BIOC_CIRCRNAPROFILER:" > versions.yml
    echo "    circrnaprofiler: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CIRCRNAPROFILER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CIRCRNAPROFILER(ch_input)

    emit:
    results  = BIOC_CIRCRNAPROFILER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CIRCRNAPROFILER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CIRCRNAPROFILER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CIRCRNAPROFILER.out.versions  // channel: path(versions.yml)
}
