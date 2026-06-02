#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ncdfFlow
// Provides HDF5 storage based methods and functions for manipulation of flow cytometry data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ncdfFlow/inst/doc/ncdfFlow.R
// Upstream  : flowStats
// Downstream: ggcyto
//
// Install: BiocManager::install("ncdfFlow")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NCDFFLOW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ncdfflow"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ncdfflow:2.52.1--r44_0' :
        'quay.io/biocontainers/bioconductor-ncdfflow:2.52.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ncdfflow_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ncdfflow_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ncdfflow_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ncdfFlow)
    library(jsonlite)


    # --- Include=false [] ---
    # Key functions: set, list.files, read.ncdfFlowSet, extdata, compdata, flowCore, read.flowSet
    library(knitr)
    opts_chunk$set(
    concordance=TRUE
    )
    path<-system.file("extdata","compdata","data",package="flowCore")
    files<-list.files(path,full.names=TRUE)[1:3]
    nc1 <- read.ncdfFlowSet(files=files)
    nc1
    fs1  <- read.flowSet(files=files)

    # --- Unlink [] ---
    # Key functions: unlink, read.ncdfFlowSet, sampleNames
    unlink(nc1)
    rm(nc1)
    nc1  <- read.ncdfFlowSet(files=files, isWriteSlice= FALSE)
    nc1[[1]]
    targetSampleName<-sampleNames(fs1)[1]
    nc1[[targetSampleName]] <- fs1[[1]]
    nc1[[1]]
    nc1[[2]]

    # --- Is Empty [] ---
    # Key functions: clone.ncdfFlowSet, sampleNames, unlink, pData, ncdfFlowSet
    nc2 <- clone.ncdfFlowSet(nc1, isEmpty = TRUE)
    nc2[[1]]
    nc2[[sampleNames(fs1)[1]]] <- fs1[[1]]
    nc2[[1]]
    unlink(nc2)
    rm(nc2)

    unlink(nc1)
    rm(nc1)
    data(GvHD)
    GvHD <- GvHD[pData(GvHD)$Patient %in% 6:7][1:4]
    nc1<-ncdfFlowSet(GvHD)

    # --- Ncdf Flow Settofs [] ---
    # Key functions: as.flowSet, phenoData, pData, varLabels, varMetadata, sampleNames, keyword, identifier
    fs1<-as.flowSet(nc1,top=2)
    phenoData(nc1)
    pData(nc1)
    varLabels(nc1)
    varMetadata(nc1)
    sampleNames(nc1)
    keyword(nc1,"FILENAME")
    identifier(nc1)
    colnames(nc1)
    colnames(nc1,prefix="s6a01")
    length(nc1)
    nm<-sampleNames(nc1)[1]
    expr1<-paste("nc1$'",nm,"'",sep="")
    eval(parse(text=expr1))
    nc1[[nm]]

    nm<-sampleNames(nc1)[c(1,3)]
    nc2<-nc1[nm]
    summary(nc2)

    # --- Fs Apply [] ---
    # Key functions: fsApply, read.table, compensation, summary, compensate, unlink, arcsinhTransform, transform
    fsApply(nc1,range)
    fsApply(nc1, each_col, median)
    cfile <- system.file("extdata","compdata","compmatrix", package="flowCore")
    comp.mat <- read.table(cfile, header=TRUE, skip=2, check.names = FALSE)
    comp <- compensation(comp.mat)

    #compensation
    summary(nc1)[[1]]
    nc2<-compensate(nc1, comp)
    summary(nc2)[[1]]
    unlink(nc2)
    rm(nc2)
    rectGate <- rectangleGate(filterId="nonDebris","FSC-H"=c(200,Inf))
    fr <- filter(nc1,rectGate)
    summary(fr)

    rg2 <- rectangleGate(filterId="nonDebris","FSC-H"=c(300,Inf))
    rg3 <- rectangleGate(filterId="nonDebris","FSC-H"=c(400,Inf))
    flist <- list(rectGate, rg2, rg3)
    names(flist) <- sampleNames(nc1[1:3])

    # --- Subsetting [] ---
    # Key functions: summary, norm2Filter, quadGate, filter, split
    nc2 <- Subset(nc1,rectGate)
    summary(nc2[[1]])
    library(flowStats)
    morphGate <- norm2Filter("FSC-H", "SSC-H", filterId = "MorphologyGate",scale = 2)
    smaller <- Subset(nc1[c(1,3)], morphGate,c("FSC-H", "SSC-H"))
    smaller[[1]]
    nc1[[1]]
    rm(smaller)
    ##splitting by a gate
    qGate <- quadGate(filterId="qg", "FSC-H"=200, "SSC-H"=400)
    fr<-filter(nc1,qGate)
    ncList<-split(nc1,fr)
    ncList
    nc1[[1]]
    ncList[[2]][[1]]
    ncList[[1]][[1]]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ncdfflow_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ncdfflow_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ncdfflow_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NCDFFLOW:", paste0("    ncdfflow: ", packageVersion("ncdfFlow"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ncdfflow_results.csv
    touch ${prefix}_ncdfflow_output.rds
    echo "BIOC_NCDFFLOW:" > versions.yml
    echo "    ncdfflow: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NCDFFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NCDFFLOW(ch_input)

    emit:
    results  = BIOC_NCDFFLOW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NCDFFLOW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NCDFFLOW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NCDFFLOW.out.versions  // channel: path(versions.yml)
}
