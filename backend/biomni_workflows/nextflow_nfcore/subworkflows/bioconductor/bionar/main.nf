#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BioNAR
// the R package BioNAR, developed to step by step analysis of PPI network. The aim is to quantify and 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BioNAR/inst/doc/BioNAR_overview.R
// Upstream  : devtools, plotly
// Downstream: none
//
// Install: BiocManager::install("BioNAR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIONAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bionar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bionar:1.8.1--r44_0' :
        'quay.io/biocontainers/bioconductor-bionar:1.8.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bionar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bionar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bionar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BioNAR)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ecdf, ggplot, theme
    Fn  <- ecdf(conmat[lower.tri(conmat)])
    X<-seq(0,1,length.out=steps+1)
    cdf<-Fn(X)
    # --- Network analysis [] ---
    # Key functions: buildNetwork, read_graph, annotateGeneNames, any, annotateTopOntoOVG, annotateSCHanno, annotatePresynaptic, annotateGOont
    afile<-system.file("extdata", "flatfile_human_gene2HDO.csv", package = "BioNAR")
    dis <- read.table(afile,sep="\t",skip=1,header=FALSE,strip.white=TRUE,quote="")
    gg <- annotateTopOntoOVG(gg, dis)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bionar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bionar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bionar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIONAR:", paste0("    bionar: ", packageVersion("BioNAR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bionar_results.csv
    touch ${prefix}_bionar_output.rds
    echo "BIOC_BIONAR:" > versions.yml
    echo "    bionar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIONAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIONAR(ch_input)

    emit:
    results  = BIOC_BIONAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIONAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIONAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIONAR.out.versions  // channel: path(versions.yml)
}
