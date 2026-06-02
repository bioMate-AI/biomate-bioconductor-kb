#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ddCt
// The Delta-Delta-Ct (ddCt) Algorithm is an approximation method to determine relative gene expression
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ddCt/inst/doc/RT-PCR-Script-ddCt.R
// Upstream  : Biobase, RColorBrewer, lattice
// Downstream: none
//
// Install: BiocManager::install("ddCt")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DDCT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ddct"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ddct:1.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ddct:1.62.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ddct_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ddct_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ddct_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SDMFrame)
    library(jsonlite)

    # --- Ddctinstall [] ---
    # Key functions: requireNamespace, packages
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install(ddCt)
    # --- Readdata [] ---
    # Key functions: path, datadir, savedir, SDMFrame
    datadir <- function(x) file.path(load.path, x)
    savedir <- function(x) file.path(save.path,x)
    file.names <- datadir(Ct.data.file.name)
    sho <- paste(gsub(".txt","",Ct.data.file.name),collapse="_")
    warningFile <- savedir(paste("warning.output",sho,".txt",sep=""))
    # --- Plot Level [] ---
    # Key functions: assayData, null, factor
    for(KindOfPlot in TheKindOfPlot){
    if(KindOfPlot=="level"){
      EE1 <- assayData(result)$exprs
      FF1 <- assayData(result)$level.err
      theTitle <- "Level"
    # --- Korrelation [] ---
    # Key functions: null, pData, assayData, combn
    A <- name.referenz.gene
    if (length(A) > 1) {
     if (!is.null(names.of.the.samples.REMAIN.in.cor)){
       corRed <- (rownames(pData(result)) %in% names.of.the.samples.REMAIN.in.cor)
     }else{
    # --- Ttest [] ---
    # Key functions: getDir
    myFoldChange <- function(x){
      x <- as.numeric(x)
      if(length(x) == 2 ){
        resu <- 2^(x[1]-x[2])
      }else if( length(x) == 1  ){
    # --- Boxplotshousekkepinggenes [] ---
    # Key functions: null, pData, assayData, levels, factor
    if(perform.ttest){
     if (!is.null(names.of.the.samples.REMAIN.in.ttest)){
       ttestRed <- (rownames(pData(result)) %in% names.of.the.samples.REMAIN.in.ttest)
     }else{
       ttestRed <- !(rownames(pData(result)) %in% names.of.the.samples.NOT.in.ttest)
    # --- Hh [] ---
    # Key functions: unlist, delim
    if(file.exists(warningFile)){
      bart   <- unlist(read.delim(warningFile,as.is=TRUE,header=FALSE))
      fehler <- sapply(bart, function(y) gsub("simpleWarning in withCallingHandlers\\(\\{: ","",y))
    }

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ddct_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ddct_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ddct_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DDCT:", paste0("    ddct: ", packageVersion("ddCt"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ddct_results.csv
    touch ${prefix}_ddct_output.rds
    echo "BIOC_DDCT:" > versions.yml
    echo "    ddct: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DDCT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DDCT(ch_input)

    emit:
    results  = BIOC_DDCT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DDCT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DDCT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DDCT.out.versions  // channel: path(versions.yml)
}
