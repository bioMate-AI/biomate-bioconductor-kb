#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fastLiquidAssociation
// This package extends the function of the LiquidAssociation package for genome-wide application. It i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/fastLiquidAssociation/inst/doc/fastLiquidAssociation.R
// Upstream  : GOstats, LiquidAssociation, WGCNA, doParallel, impute
// Downstream: none
//
// Install: BiocManager::install("fastLiquidAssociation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FASTLIQUIDASSOCIATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fastliquidassociation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fastliquidassociation:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fastliquidassociation:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_fastliquidassociation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fastliquidassociation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fastliquidassociation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNM)
    library(GLA)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: na, exprs
    library(fastLiquidAssociation)
    suppressMessages(library(yeastCC))
    suppressMessages(library(org.Sc.sgd.db))
    data(spYCCES)
    lae <- spYCCES[,-(1:4)]
    # --- Calculate Top Mla [] ---
    # Key functions: detectCores, fastMLA
    detectCores()
    example <- fastMLA(data=data,topn=50,nvec=1:5,rvalue=0.5,cut=4,threads=detectCores())
    example[1:5,]
    # --- Stopcluster1 [] ---
    # Key functions: stopImplicitCluster, closeAllConnections
    stopImplicitCluster()
    # closeAllConnections()
    # --- Calculate Cnm [] ---
    # Key functions: CNM
    #from our example with fastMLA
    CNMcalc <- mass.CNM(data=data,GLA.mat=example,nback=5)
    CNMcalc
    # --- Calculate Cnm Boots [] ---
    # Key functions: exprs, CNM
    fulldata <- t(exprs(lae))
    load(system.file('data','testmat.RData',package='fastLiquidAssociation'))
    notsense <- testmat
    CNMother <- mass.CNM(data=fulldata,GLA.mat=notsense,nback=5)
    CNMother
    # --- Time Comparison [] ---
    # Key functions: makeCluster, detectCores, registerDoParallel
    #determine number of processors for multicore systems
    clust <- makeCluster(detectCores())
    registerDoParallel(clust)
    boottrips <- CNMother[[2]]
    dim(boottrips)
    # --- Speed Test [] ---
    # Key functions: time, GLA, stopCluster
    #We take the results for the single triplet and put it in matrix format
    example.boots <- boottrips[1, , drop = FALSE]
    dim(example.boots)
    set.seed(1)
    system.time(GLAnew <- fastboots.GLA(tripmat=example.boots,data=fulldata,
    # --- Extend Example [] ---
    # Key functions: new, hyperGTest
    library(GOstats)
    library("org.Sc.sgd.db")
    ##X3 genes
    topX3 <- unique(example[,3])
    hyp.cutoff <- 0.05
    # --- Obtain Gene List [] ---
    # Key functions: intersect, mappedkeys
    ###extracts GO list elements of summary(hyperGtestobj)<cutoff
    ###converts ORFids to Gene names and returns under GO list element
    ##for ontology BP
    GOids <- summary(GOout,categorySize=5)$GOBPID
    check <- GOout@goDag@nodeData@data

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fastliquidassociation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fastliquidassociation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fastliquidassociation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FASTLIQUIDASSOCIATION:", paste0("    fastliquidassociation: ", packageVersion("fastLiquidAssociation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fastliquidassociation_results.csv
    touch ${prefix}_fastliquidassociation_output.rds
    echo "BIOC_FASTLIQUIDASSOCIATION:" > versions.yml
    echo "    fastliquidassociation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FASTLIQUIDASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    BIOC_FASTLIQUIDASSOCIATION(ch_input)

    emit:
    results  = BIOC_FASTLIQUIDASSOCIATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FASTLIQUIDASSOCIATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FASTLIQUIDASSOCIATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FASTLIQUIDASSOCIATION.out.versions  // channel: path(versions.yml)
}
