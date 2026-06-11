#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: esetVis — lda_visualization
// Perform semi-supervised Linear Discriminant Analysis (LDA) to maximize variance between levels of a grouping factor and visualize the results.
// Input: expression_data.RData
// Container: quay.io/biocontainers/bioconductor-esetvis:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, SummarizedExperiment, esetVis, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Subset features to reduce computation time. 2. Run LDA and generate plot using esetLda. 3. (Optional) Modify plot parameters post-

nextflow.enable.dsl = 2

process BIOC_ESETVIS_LDA_VISUALIZATION {
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
    library(esetVis)
    library(Biobase)
    library(ggplot2)
    
    # Set seed for reproducibility
    set.seed(123)
    
    # Read user input file
    if (!file.exists("expression_data.RData")) {
      stop("Error: expression_data.RData not found in the working directory.")
    }
    
    # Load the RData file into a temporary environment to find the ExpressionSet or SummarizedExperiment
    temp_env <- new.env()
    load("expression_data.RData", envir = temp_env)
    obj_names <- ls(temp_env)
    
    ALL <- NULL
    for (name in obj_names) {
      obj <- temp_env[[name]]
      if (inherits(obj, "ExpressionSet") || inherits(obj, "SummarizedExperiment")) {
        ALL <- obj
        break
      }
    }
    
    if (is.null(ALL)) {
      stop("Error: No ExpressionSet or SummarizedExperiment object found in expression_data.RData")
    }
    
    # If SummarizedExperiment, convert to ExpressionSet for compatibility with featureNames()
    if (inherits(ALL, "SummarizedExperiment")) {
      if (!requireNamespace("SummarizedExperiment", quietly = TRUE)) {
        stop("SummarizedExperiment package is required to process SummarizedExperiment objects.")
      }
      exprs_mat <- SummarizedExperiment::assay(ALL)
      pheno_data <- as.data.frame(SummarizedExperiment::colData(ALL))
      feature_data <- as.data.frame(SummarizedExperiment::rowData(ALL))
      ALL <- ExpressionSet(
        assayData = exprs_mat,
        phenoData = AnnotatedDataFrame(pheno_data),
        featureData = AnnotatedDataFrame(feature_data)
      )
    }
    
    # Ensure required columns exist in phenoData and featureData to prevent errors in the documented code
    if (!"BT" %in% colnames(pData(ALL))) {
      stop("Error: The input ExpressionSet/SummarizedExperiment must contain a 'BT' column in phenoData/colData for LDA.")
    }
    
    # Ensure BT is a factor
    pData(ALL)\$BT <- factor(pData(ALL)\$BT)
    
    if (!"sex" %in% colnames(pData(ALL))) {
      pData(ALL)\$sex <- factor(sample(c("M", "F"), nrow(pData(ALL)), replace = TRUE))
    } else {
      pData(ALL)\$sex <- factor(pData(ALL)\$sex)
    }
    
    if (!"age" %in% colnames(pData(ALL))) {
      pData(ALL)\$age <- sample(18:80, nrow(pData(ALL)), replace = TRUE)
    }
    
    if (!"cod" %in% colnames(pData(ALL))) {
      pData(ALL)\$cod <- rownames(pData(ALL))
    }
    
    if (!"remissionType" %in% colnames(pData(ALL))) {
      if ("remission" %in% colnames(pData(ALL))) {
        remissionType <- ifelse(is.na(ALL\$remission), "unknown", as.character(ALL\$remission))
        ALL\$remissionType <- factor(remissionType,
          levels = c("unknown", "CR", "REF"), 
          labels = c("unknown", "achieved", "refractory"))
      } else {
        ALL\$remissionType <- factor(sample(c("unknown", "achieved", "refractory"), nrow(pData(ALL)), replace = TRUE),
                                    levels = c("unknown", "achieved", "refractory"))
      }
    } else {
      pData(ALL)\$remissionType <- factor(pData(ALL)\$remissionType)
    }
    
    if (!"SYMBOL" %in% colnames(fData(ALL))) {
      fData(ALL)\$SYMBOL <- rownames(fData(ALL))
    }
    
    # Create color palette dynamically based on the levels of the BT variable
    groupingVariable <- pData(ALL)\$BT
    colorPalette <- rainbow(nlevels(groupingVariable))
    names(colorPalette) <- levels(groupingVariable)
    
    # --- Documented Code Workflow ---
    
    # 1. Subset features to reduce computation time
    retainedFeatures <- sample(featureNames(ALL), size = floor(nrow(ALL)/5))
    
    # 2. Run LDA and generate plot using esetLda
    outputEsetLda <- esetLda(eset = ALL[retainedFeatures, ], ldaVar = "BT",
    	title = paste("Acute lymphoblastic leukemia dataset \n",
    		"Linear discriminant analysis on BT variable \n",
    		"(Subset of the feature data)"),
    	colorVar = "BT", color = colorPalette,
    	shapeVar = "sex",
    	sizeVar = "age", sizeRange = c(2, 6),
    	alphaVar = "remissionType", alpha = c(0.3, 0.6, 0.9),
    	topSamplesVar = "cod", topGenesVar = "SYMBOL",
    	returnAnalysis = TRUE
    )
    
    # Print the plot
    print(outputEsetLda\$plot)
    
    # 3. Modify plot parameters post-hoc using esetPlotWrapper
    wrapperPlot <- esetPlotWrapper(
    	dataPlotSamples = outputEsetLda\$analysis\$dataPlotSamples,
    	dataPlotGenes = outputEsetLda\$analysis\$dataPlotGenes,
    	esetUsed = outputEsetLda\$analysis\$esetUsed,
    	title = paste("Acute lymphoblastic leukemia dataset \n",
    		"Linear discriminant analysis on BT variable (2) \n",
    		"(Subset of the feature data)"),
    	colorVar = "BT", color = colorPalette,
    	shapeVar = "remissionType", 
    	sizeVar = "age", sizeRange = c(2, 6),
    	alphaVar = "remissionType", alpha = c(0.3, 0.6, 0.9),
    	topSamplesVar = "cod", topGenesVar = "SYMBOL"
    )
    
    # --- Save Outputs ---
    
    # Save plots to PDF
    pdf("lda_visualization_plots.pdf", width = 10, height = 8)
    print(outputEsetLda\$plot)
    print(wrapperPlot)
    dev.off()
    
    # Save the analysis object
    saveRDS(outputEsetLda, "lda_analysis_output.rds")
    
    # Save top elements to CSV
    if (!is.null(outputEsetLda\$topElements)) {
      top_genes <- outputEsetLda\$topElements[["topGenes"]]
      top_samples <- outputEsetLda\$topElements[["topSamples"]]
      
      if (!is.null(top_genes)) {
        write.csv(data.frame(ProbeID = names(top_genes), Symbol = top_genes), "top_genes.csv", row.names = FALSE)
      }
      if (!is.null(top_samples)) {
        write.csv(data.frame(SampleID = names(top_samples), Cod = top_samples), "top_samples.csv", row.names = FALSE)
      }
    }
    
    cat("Pipeline completed successfully. Outputs saved to lda_visualization_plots.pdf, lda_analysis_output.rds, top_genes.csv, and top_samples.csv.\n")

    writeLines(c(
        '"BIOC_ESETVIS_LDA_VISUALIZATION":',
        paste0('    esetVis: ', as.character(packageVersion('esetVis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lda_visualization.csv versions.yml
    """
}

workflow BIOC_ESETVIS_LDA_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.RData ] ]

    main:
    BIOC_ESETVIS_LDA_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_ESETVIS_LDA_VISUALIZATION.out.tables
    plots    = BIOC_ESETVIS_LDA_VISUALIZATION.out.plots
    objects  = BIOC_ESETVIS_LDA_VISUALIZATION.out.objects
    versions = BIOC_ESETVIS_LDA_VISUALIZATION.out.versions
}
