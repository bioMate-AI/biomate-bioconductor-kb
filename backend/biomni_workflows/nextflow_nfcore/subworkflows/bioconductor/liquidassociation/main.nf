#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: LiquidAssociation — triplet_liquid_association_analysis
// Estimate and test liquid association for a specific gene triplet of interest.
// Input: data, eSetdata
// Container: quay.io/biocontainers/bioconductor-liquidassociation:1.64.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, LiquidAssociation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot conditional distributions using plotGLA
//  * 2. [Core Analysis] Calculate direct estimates using LA and GLA
//  * 3. [Core Analysis] Fit the conditional normal model using CNM.full
//  * 4. [Core Analysis] Perform hypothesis testing using getsGLA and getsLA

nextflow.enable.dsl = 2

process BIOC_LIQUIDASSOCIATION_TRIPLET_LIQUID_ASSOCIATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(LiquidAssociation)
    library(Biobase)
    
    # Read user input files from the working directory
    data <- readRDS("data.rds")
    eSetdata <- readRDS("eSetdata.rds")
    
    # Dynamically construct geneMap from the input data
    # geneMap maps gene names (colnames of data) to probe IDs (rownames of eSetdata)
    geneMap <- rownames(eSetdata)
    names(geneMap) <- colnames(data)
    
    # Stage 1: Plot conditional distributions using plotGLA
    # This will save a plot file named "GLAplot.pdf" (or similar format depending on the package's device defaults)
    plotGLA(data, cut=3, dim=3, pch=16, filen="GLAplot", save=TRUE)
    
    # Stage 2: Calculate direct estimates using LA and GLA
    LAest <- LA(data)
    GLAest <- rep(0, 3)
    for (dim in 1:3) {
      GLAest[dim] <- GLA(data, cut=4, dim=dim)		
    }
    eSetGLA <- GLA(eSetdata, cut=4, dim=3, geneMap=geneMap)
    
    # Stage 3: Fit the conditional normal model using CNM.full
    FitCNM.full <- CNM.full(data)
    
    # Stage 4: Perform hypothesis testing using getsGLA and getsLA
    sGLAest <- getsGLA(data, boots=20, perm=50, cut=4, dim=3)
    sLAest <- getsLA(data, boots=20, perm=50)
    
    # Save meaningful results to output files
    saveRDS(LAest, "LAest.rds")
    saveRDS(GLAest, "GLAest.rds")
    saveRDS(eSetGLA, "eSetGLA.rds")
    saveRDS(FitCNM.full, "FitCNM_full.rds")
    saveRDS(sGLAest, "sGLAest.rds")
    saveRDS(sLAest, "sLAest.rds")
    
    # Write a comprehensive text summary of the results
    sink("liquid_association_summary.txt")
    cat("=========================================================\n")
    # Write a comprehensive text summary of the results
    cat("Liquid Association Analysis Summary\n")
    cat("=========================================================\n\n")
    
    cat("1. Direct LA Estimate:\n")
    print(LAest)
    cat("\n")
    
    cat("2. Generalized LA (GLA) Estimates (dim 1 to 3):\n")
    print(GLAest)
    cat("\n")
    
    cat("3. ExpressionSet GLA Estimate:\n")
    print(eSetGLA)
    cat("\n")
    
    cat("4. Conditional Normal Model (CNM.full) Fit:\n")
    print(FitCNM.full)
    cat("\n")
    
    cat("5. Hypothesis Testing (sGLA):\n")
    print(sGLAest)
    cat("\n")
    
    cat("6. Hypothesis Testing (sLA):\n")
    print(sLAest)
    cat("\n")
    sink()

    writeLines(c(
        '"BIOC_LIQUIDASSOCIATION_TRIPLET_LIQUID_ASSOCIATION_ANALYSIS":',
        paste0('    LiquidAssociation: ', as.character(packageVersion('LiquidAssociation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_triplet_liquid_association_analysis.csv versions.yml
    """
}

workflow BIOC_LIQUIDASSOCIATION_TRIPLET_LIQUID_ASSOCIATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data, eSetdata ] ]

    main:
    BIOC_LIQUIDASSOCIATION_TRIPLET_LIQUID_ASSOCIATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_LIQUIDASSOCIATION_TRIPLET_LIQUID_ASSOCIATION_ANALYSIS.out.tables
    plots    = BIOC_LIQUIDASSOCIATION_TRIPLET_LIQUID_ASSOCIATION_ANALYSIS.out.plots
    objects  = BIOC_LIQUIDASSOCIATION_TRIPLET_LIQUID_ASSOCIATION_ANALYSIS.out.objects
    versions = BIOC_LIQUIDASSOCIATION_TRIPLET_LIQUID_ASSOCIATION_ANALYSIS.out.versions
}
