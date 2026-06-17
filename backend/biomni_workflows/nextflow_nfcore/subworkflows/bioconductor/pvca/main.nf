#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pvca — pvca_batch_assessment
// Quantify and visualize the proportion of variance in transcriptomics data attributable to batch effects, biological factors, and their two-way interactions.
// Input: ExpressionSet
// Container: quay.io/biocontainers/bioconductor-pvca:1.50.0--r45hdfd78af_0
// R packages: Biobase, golubesets, pvca
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, pvca
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and input data
//  * 2. [Input & Preparation] Define the PCA variance threshold and the metadata factors to assess
//  * 3. [Core Analysis] Run pvcaBatchAssess to perform PVCA and estimate variance components
//  * 4. [Visualization & Output] Plot the resulting proportions of variance as a bar chart

nextflow.enable.dsl = 2

process BIOC_PVCA_PVCA_BATCH_ASSESSMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("Biobase", "golubesets", "pvca")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(pvca)
    
    # 1. Load the input ExpressionSet from the working directory
    input_file <- "ExpressionSet.rds"
    if (!file.exists(input_file)) {
      # Fallback: search for any RDS file if the exact name is slightly different
      rds_files <- list.files(pattern = "\\\\.rds\$", ignore.case = TRUE)
      if (length(rds_files) > 0) {
        input_file <- rds_files[1]
      } else {
        stop("Error: ExpressionSet (RDS file) not found in the working directory.")
      }
    }
    
    Golub_Merge <- readRDS(input_file)
    
    # Ensure the loaded object is indeed an ExpressionSet
    if (!inherits(Golub_Merge, "ExpressionSet")) {
      stop("Error: The loaded object is not of class 'ExpressionSet'.")
    }
    
    # 2. Define the PCA variance threshold and the metadata factors to assess
    pct_threshold <- 0.6
    
    # Determine batch factors: use documented defaults if they exist, 
    # otherwise dynamically select suitable categorical columns from phenoData
    default_factors <- c("ALL.AML", "BM.PB", "Source")
    if (all(default_factors %in% colnames(Biobase::pData(Golub_Merge)))) {
      batch.factors <- default_factors
    } else {
      pd <- Biobase::pData(Golub_Merge)
      # Select columns that are factors/characters/integers with > 1 and < N unique values
      suitable_cols <- sapply(pd, function(col) {
        num_unique <- length(unique(col))
        num_unique > 1 && num_unique < nrow(pd) && (is.factor(col) || is.character(col) || is.integer(col))
      })
      batch.factors <- names(suitable_cols)[suitable_cols]
      if (length(batch.factors) > 3) {
        batch.factors <- batch.factors[1:3]
      }
      if (length(batch.factors) == 0) {
        stop("Error: No suitable metadata factors found in the ExpressionSet for PVCA analysis.")
      }
    }
    
    # 3. Run pvcaBatchAssess to perform PVCA and estimate variance components
    pvcaObj <- pvcaBatchAssess (Golub_Merge, batch.factors, pct_threshold)
    
    # 4. Plot the resulting proportions of variance as a bar chart and save to PDF
    pdf("pvca_barplot.pdf", width = 8, height = 6)
    bp <- barplot(pvcaObj\$dat,  xlab = "Effects", 
    	ylab = "Weighted average proportion variance", 
    	ylim= c(0,1.1),col = c("blue"), las=2, 
    	main="PVCA estimation bar chart")
    axis(1, at = bp, labels = pvcaObj\$label, xlab = "Effects", cex.axis = 0.5, las=2)
    values = pvcaObj\$dat
    new_values = round(values , 3)
    text(bp,pvcaObj\$dat,labels = new_values, pos=3, cex = 0.8)
    dev.off()
    
    # 5. Save numerical results to CSV and the PVCA object to RDS
    results_df <- data.frame(
      Effect = pvcaObj\$label,
      ProportionVariance = pvcaObj\$dat,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "pvca_results.csv", row.names = FALSE)
    saveRDS(pvcaObj, "pvca_object.rds")

    writeLines(c(
        '"BIOC_PVCA_PVCA_BATCH_ASSESSMENT":',
        paste0('    pvca: ', as.character(packageVersion('pvca')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pvca_batch_assessment.csv versions.yml
    """
}

workflow BIOC_PVCA_PVCA_BATCH_ASSESSMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet ] ]

    main:
    BIOC_PVCA_PVCA_BATCH_ASSESSMENT(ch_input)

    emit:
    tables   = BIOC_PVCA_PVCA_BATCH_ASSESSMENT.out.tables
    plots    = BIOC_PVCA_PVCA_BATCH_ASSESSMENT.out.plots
    objects  = BIOC_PVCA_PVCA_BATCH_ASSESSMENT.out.objects
    versions = BIOC_PVCA_PVCA_BATCH_ASSESSMENT.out.versions
}
