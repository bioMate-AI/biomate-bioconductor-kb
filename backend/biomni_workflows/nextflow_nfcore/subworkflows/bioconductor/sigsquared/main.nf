#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sigsquared — gene_signature_survival_optimization
// Train threshold parameters for a linear signaling pathway gene signature and apply them to predict patient survival outcomes.
// Input: dataSet.RData
// Container: quay.io/biocontainers/bioconductor-sigsquared:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, sigsquared, survival
// Visualizations: survival plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a new geneSignature object
//  * 2. [Core Analysis] Set the gene signature directionality and gene names using setGeneSignature
//  * 3. [Core Analysis] Run the optimization and cross-validation pipeline using analysisPipeline
//  * 4. [Core Analysis] Apply the trained thresholds to the dataset using ensembleAdjustable
//  * 5. [Visualization & Output] Plot the survival curves using survfit and plot

nextflow.enable.dsl = 2

process BIOC_SIGSQUARED_GENE_SIGNATURE_SURVIVAL_OPTIMIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "survival", "sigsquared")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(Biobase)
    library(survival)
    library(sigsquared)
    
    # 1. Load the user-provided dataSet.RData and extract the ExpressionSet
    if (!file.exists("dataSet.RData")) {
      stop("Error: 'dataSet.RData' not found in the working directory.")
    }
    
    load_env <- new.env()
    load("dataSet.RData", envir = load_env)
    
    # Find the ExpressionSet object in the loaded environment
    eset_name <- ls(load_env)[sapply(ls(load_env), function(x) inherits(load_env[[x]], "ExpressionSet"))]
    if (length(eset_name) == 0) {
      stop("Error: No ExpressionSet object found in dataSet.RData")
    }
    
    # Assign the ExpressionSet to BrCa443 to match the documented code variable name
    BrCa443 <- load_env[[eset_name[1]]]
    
    # 2. Create a new geneSignature object and set its parameters
    gs <- new("geneSignature")
    genes <- c("RKIP", "HMGA2", "SPP1", "CXCR4", "MMP1", "MetaLET7", "MetaBACH1")
    gs <- setGeneSignature(gs, direct=c(-1, 1, 1, 1, 1, 1, 1), genes=genes)
    
    # 3. Run the optimization and cross-validation pipeline
    gs <- analysisPipeline(dataSet=BrCa443, geneSig=gs, iterPerK=50, k=2, rand=FALSE)
    
    # 4. Apply the trained thresholds to the dataset
    s <- ensembleAdjustable(dataSet=BrCa443, geneSig=gs)
    
    # 5. Plot the survival curves and save to PDF
    pdf("survival_plot.pdf", width=7, height=7)
    plot(survfit(Surv(MFS, met) ~ s, data=pData(BrCa443)), 
         col=c("blue", "red"), 
         xlab="Months", 
         ylab="Metastasis-Free Survival Probability",
         main="Survival Curve by Gene Signature Ensemble")
    dev.off()
    
    # 6. Save the optimized gene signature object
    saveRDS(gs, "optimized_gene_signature.rds")
    
    # 7. Save the predictions and metadata to a CSV file
    results_df <- data.frame(
      Sample = sampleNames(BrCa443),
      EnsembleScore = s,
      MFS = pData(BrCa443)\$MFS,
      met = pData(BrCa443)\$met
    )
    write.csv(results_df, "survival_predictions.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_SIGSQUARED_GENE_SIGNATURE_SURVIVAL_OPTIMIZATION":',
        paste0('    sigsquared: ', as.character(packageVersion('sigsquared')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_signature_survival_optimization.csv versions.yml
    """
}

workflow BIOC_SIGSQUARED_GENE_SIGNATURE_SURVIVAL_OPTIMIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataSet.RData ] ]

    main:
    BIOC_SIGSQUARED_GENE_SIGNATURE_SURVIVAL_OPTIMIZATION(ch_input)

    emit:
    tables   = BIOC_SIGSQUARED_GENE_SIGNATURE_SURVIVAL_OPTIMIZATION.out.tables
    plots    = BIOC_SIGSQUARED_GENE_SIGNATURE_SURVIVAL_OPTIMIZATION.out.plots
    objects  = BIOC_SIGSQUARED_GENE_SIGNATURE_SURVIVAL_OPTIMIZATION.out.objects
    versions = BIOC_SIGSQUARED_GENE_SIGNATURE_SURVIVAL_OPTIMIZATION.out.versions
}
