#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NanoStringDiff
// This Package utilizes a generalized linear model(GLM) of the negative binomial family to characteriz
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NanoStringDiff/inst/doc/NanoStringDiff.R
// Upstream  : Biobase
// Downstream: none
//
// Install: BiocManager::install("NanoStringDiff")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NANOSTRINGDIFF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nanostringdiff"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nanostringdiff:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nanostringdiff:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nanostringdiff_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nanostringdiff_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nanostringdiff_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(LRT)
    library(jsonlite)

    # --- Quick Start [] ---
    # Key functions: pData, estNormalizationFactors, LRT
    ## library("Biobase")
    ## library("NanoStringDiff")
    ## data(NanoStringData)
    ## pheno=pData(NanoStringData)
    ## design.full=model.matrix(~0+pheno$group)
    # --- Getdirectory [] ---
    # Key functions: file
    directory <- system.file("extdata", package="NanoStringDiff", mustWork=TRUE)
    path<-paste(directory,"Mori.csv",sep="/")
    # --- Makephenotypedata [] ---
    # Key functions: frame
    designs=data.frame(group=c("Normal","Normal","Tumor","Tumor"))
    designs
    # --- Csvinput [] ---
    # Key functions: createNanoStringSetFromCsv
    library("NanoStringDiff")
    NanoStringData=createNanoStringSetFromCsv(path,header=TRUE,designs)
    NanoStringData
    # --- Matrixinput [] ---
    # Key functions: rpois, frame, createNanoStringSet, pData
    endogenous=matrix(rpois(100,50),25,4)
    colnames(endogenous)=paste("Sample",1:4)
    positive=matrix(rpois(24,c(128,32,8,2,0.5,0.125)*80),6,4)
    colnames(positive)=paste("Sample",1:4)
    negative=matrix(rpois(32,10),8,4)
    # --- Makedesignmatrix1 [] ---
    # Key functions: pData
    pheno=pData(NanoStringData1)
    group=pheno$group
    design.full=model.matrix(~0+group)
    design.full
    # --- Getcontrols [] ---
    # Key functions: estNormalizationFactors, positiveFactor, negativeFactor, housekeepingFactor
    NanoStringData1=estNormalizationFactors(NanoStringData1)
    positiveFactor(NanoStringData1)
    negativeFactor(NanoStringData1)
    housekeepingFactor(NanoStringData1)
    # --- Result1 [] ---
    # Key functions: LRT
    result=glm.LRT(NanoStringData1,design.full,contrast=contrast)
    head(result$table)
    str(result)
    # --- Createpseudodata [] ---
    # Key functions: rpois, frame, createNanoStringSet
    endogenous=matrix(rpois(300,50),25,12)
    colnames(endogenous)=paste("Sample", 1:12)
    colnames(endogenous)=paste("Sample",1:12)
    positive=matrix(rpois(72,c(128,32,8,2,0.5,0.125)*80),6,12)
    negative=matrix(rpois(96,10),8,12)
    # --- Makedesignmatrix2 [] ---
    # Key functions: pData
    pheno=pData(NanoStringData2)
    group=pheno$group
    design.full=model.matrix(~0+group)
    design.full
    # --- Assignsizefactors [] ---
    # Key functions: estNormalizationFactors
    NanoStringData2=estNormalizationFactors(NanoStringData2)
    # --- Result2 [] ---
    # Key functions: LRT
    ## result=glm.LRT(NanoStringData2,design.full,contrast=c(-1,1,0))
    # --- Result3 [] ---
    # Key functions: LRT
    ## result=glm.LRT(NanoStringData2,design.full,contrast=c(-1,0,1))
    # --- Result4 [] ---
    # Key functions: LRT
    ## result=glm.LRT(NanoStringData2,design.full,contrast=c(0,1,-1))
    # --- Result5 [] ---
    # Key functions: LRT
    ## result=glm.LRT(NanoStringData2,design.full,Beta=2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nanostringdiff_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nanostringdiff_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nanostringdiff_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NANOSTRINGDIFF:", paste0("    nanostringdiff: ", packageVersion("NanoStringDiff"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nanostringdiff_results.csv
    touch ${prefix}_nanostringdiff_output.rds
    echo "BIOC_NANOSTRINGDIFF:" > versions.yml
    echo "    nanostringdiff: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NANOSTRINGDIFF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NANOSTRINGDIFF(ch_input)

    emit:
    results  = BIOC_NANOSTRINGDIFF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NANOSTRINGDIFF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NANOSTRINGDIFF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NANOSTRINGDIFF.out.versions  // channel: path(versions.yml)
}
