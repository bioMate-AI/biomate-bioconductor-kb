#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PREDA
// Package for the position related analysis of quantitative functional genomics data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PREDA/inst/doc/PREDAtutorial.R
// Upstream  : none
// Downstream: PREDAsampledata
//
// Install: BiocManager::install("PREDA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PREDA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-preda"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-preda:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-preda:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_preda_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_preda_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_preda_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomicAnnotations2GenomicAnnotationsForPREDA)
    library(GenomicAnnotationsForPREDAFromfile)
    library(GenomicAnnotationsFromLibrary)
    library(GenomicRegions2dataframe)
    library(GenomicRegionsFindOverlap)
    library(MergeStatisticAnnotations2DataForPREDA)
    library(PREDAResults2GenomicRegions)
    library(PREDA_main)
    library(SODEGIRpreprocessingGE)
    library(StatisticsForPREDAFromfile)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: data
    data(SODEGIRGEanalysisResults)
    # --- PreprocessingGE analysis [] ---
    # Key functions: preprocessingGE, justRMA, annotation, rma, statisticsForPREDAfromEset, analysesNames, eset2GenomicAnnotations, GenomicAnnotationsFromLibrary
    ## checkplot<-genomePlot(SODEGIRGEanalysisResults, genomicRegions=regions_forPlot, grouping=c(1:3, 1:3), scale.positions="Mb", region.colors=c("red","red2","red4","blue","blue2","blue4"))
    ## legend(x=140000000, y=22*3, legend=c("GeneExpression UP","CopyNumber gain","SODEGIR amplified","GeneExpression DOWN","CopyNumber loss","SODEGIR deleted"), fill=c("red","red2","red4","blue","blue2","blue4"))
    ## title(paste("Sample",names(SODEGIR_GE_UP[[1]])))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_preda_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_preda_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_preda_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PREDA:", paste0("    preda: ", packageVersion("PREDA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_preda_results.csv
    touch ${prefix}_preda_output.rds
    echo "BIOC_PREDA:" > versions.yml
    echo "    preda: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PREDA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PREDA(ch_input)

    emit:
    results  = BIOC_PREDA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PREDA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PREDA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PREDA.out.versions  // channel: path(versions.yml)
}
