#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChIPexoQual
// Package with a quality control pipeline for ChIP-exo/nexus data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ChIPexoQual/inst/doc/vignette.R
// Upstream  : BiocParallel, BiocStyle, ChIPexoQualExample, gridExtra, knitr
// Downstream: none
//
// Install: BiocManager::install("ChIPexoQual")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPEXOQUAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chipexoqual"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chipexoqual:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chipexoqual:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chipexoqual_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chipexoqual_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chipexoqual_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ChIPexoQual)
    library(jsonlite)


    # --- Extraload [] ---
    # Key functions: set, center, list.files, basename, ExoData, readGAlignments, identical, GRanges
    library(dplyr,quietly = TRUE)
        library(BiocParallel)
        library(gridExtra)
        library(ChIPexoQual)
        library(ChIPexoQualExample)
        library(knitr)
        opts_chunk$set(fig.align = "center")
    files = list.files(system.file("extdata",
            package = "ChIPexoQualExample"),full.names = TRUE)
        basename(files[1])
        ex1 = ExoData(file = files[1],mc.cores = 2L,verbose = FALSE)
        ex1
        reads = readGAlignments(files[1],param = NULL)
        ex2 = ExoData(reads = reads,mc.cores = 2L,verbose = FALSE)
        identical(GRanges(ex1),GRanges(ex2))

    # --- Pre Create [] ---
    # Key functions: bai
    rm(reads,ex1,ex2)
    files = files[grep("bai",files,invert = TRUE)] ## ignore index files
        exampleExoData = lapply(files,ExoData,mc.cores = 2L,verbose = FALSE)

    # --- Depth [] ---
    # Key functions: ARCvURCplot
    sapply(exampleExoData,nreads)
    ARCvURCplot(exampleExoData,names.input = paste("Rep",1:3,sep = "-"))

    # --- Strand1 [] ---
    # Key functions: regionCompplot, FSRDistplot, grid.arrange, ARCvURCplot
    p1 = regionCompplot(exampleExoData,names.input = paste("Rep",1:3,
            sep = "-"),depth.values = seq_len(50))
        p2 = FSRDistplot(exampleExoData,names.input = paste("Rep",1:3,sep = "-"),
            quantiles = c(.25,.5,.75),depth.values = seq_len(100))
        gridExtra::grid.arrange(p1,p2,nrow = 1)
    ARCvURCplot(exampleExoData[[1]],
                     subset(exampleExoData[[1]],uniquePos > 10),
                     subset(exampleExoData[[1]],uniquePos > 20),
                     names.input = c("All", "uniquePos > 10", "uniquePos > 20"))

    # --- Param Dist [] ---
    # Key functions: paramDistBoxplot, grid.arrange, beta1, beta2, function
    p1 = paramDistBoxplot(exampleExoData,which.param = "beta1", names.input = paste("Rep",1:3,sep = "-"))
        p2 = paramDistBoxplot(exampleExoData,which.param = "beta2", names.input = paste("Rep",1:3,sep = "-"))
        gridExtra::grid.arrange(p1,p2,nrow = 1)
    sapply(exampleExoData,function(x)median(beta1(x)))
        sapply(exampleExoData,function(x)median(-beta2(x)))

    # --- Subsamping [] ---
    # Key functions: ExoDataSubsampling, paramDistBoxplot, grid.arrange, beta1, beta2
    sample.depth = seq(1e5,2e5,5e4)
        exoList = ExoDataSubsampling(file = files[3],sample.depth = sample.depth, verbose=FALSE)
    p1 = paramDistBoxplot(exoList,which.param = "beta1")
        p2 = paramDistBoxplot(exoList,which.param = "beta2")
        gridExtra::grid.arrange(p1,p2,nrow = 1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chipexoqual_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chipexoqual_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chipexoqual_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIPEXOQUAL:", paste0("    chipexoqual: ", packageVersion("ChIPexoQual"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipexoqual_results.csv
    touch ${prefix}_chipexoqual_output.rds
    echo "BIOC_CHIPEXOQUAL:" > versions.yml
    echo "    chipexoqual: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIPEXOQUAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIPEXOQUAL(ch_input)

    emit:
    results  = BIOC_CHIPEXOQUAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIPEXOQUAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIPEXOQUAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIPEXOQUAL.out.versions  // channel: path(versions.yml)
}
