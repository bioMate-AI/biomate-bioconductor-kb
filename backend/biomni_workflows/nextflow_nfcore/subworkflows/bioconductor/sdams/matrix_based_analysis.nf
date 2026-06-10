#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SDAMS — matrix_based_analysis
// Create a SummarizedExperiment object from R matrices and perform semi-parametric differential expression analysis.
// Input: featureInfo, groupInfo
// Container: quay.io/biocontainers/bioconductor-sdams:1.30.0--r45hdfd78af_0
// Requires: SDAMS
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the SDAMS package
//  * 2. [Visualization & Output] Create a SummarizedExperiment object using createSEFromMatrix
//  * 3. [Core Analysis] Run the differential expression analysis using SDA
//  * 4. [Core Analysis] Extract results for the zero-part (gamma), non-zero part (beta), and two-part test

nextflow.enable.dsl = 2

process BIOC_SDAMS_MATRIX_BASED_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SDAMS")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load the SDAMS package
    library("SDAMS")
    
    # Read the user input files from the working directory
    # featureInfo: matrix of non-negative expression values (genes as rows, cells as columns)
    # groupInfo: data frame with cell subpopulation grouping (rownames matching colnames of featureInfo)
    featureInfo_raw <- read.csv("featureInfo", row.names = 1, check.names = FALSE)
    featureInfo <- as.matrix(featureInfo_raw)
    
    groupInfo <- read.csv("groupInfo", row.names = 1, check.names = FALSE)
    
    # Ensure alignment of samples between featureInfo and groupInfo
    common_samples <- intersect(colnames(featureInfo), rownames(groupInfo))
    if (length(common_samples) == 0) {
      stop("Error: No matching sample/cell identifiers found between featureInfo and groupInfo.")
    }
    featureInfo <- featureInfo[, common_samples, drop = FALSE]
    groupInfo <- groupInfo[common_samples, , drop = FALSE]
    
    # Create a SummarizedExperiment object using createSEFromMatrix
    exampleSE2 <- createSEFromMatrix(feature = featureInfo, colData = groupInfo)
    
    # Run the differential expression analysis using SDA
    results_SC <- SDA(exampleSE2)
    
    # Extract and display results as documented
    print("Head of pv_gamma:")
    print(head(results_SC\$pv_gamma[,1]))
    
    print("Head of qv_gamma:")
    print(head(results_SC\$qv_gamma[,1]))
    
    print("Head of pv_beta:")
    print(head(results_SC\$pv_beta[,1]))
    
    print("Head of qv_beta:")
    print(head(results_SC\$qv_beta[,1]))
    
    print("Head of pv_2part:")
    print(head(results_SC\$pv_2part[,1]))
    
    print("Head of qv_2part:")
    print(head(results_SC\$qv_2part[,1]))
    
    print("Head of feat.names:")
    print(head(results_SC\$feat.names))
    
    # Write named output files for the meaningful results
    # 1. Save the complete results object as an RDS file
    saveRDS(results_SC, file = "sda_results.rds")
    
    # 2. Export a comprehensive CSV table of the results
    results_df <- data.frame(
      Feature = results_SC\$feat.names,
      pv_gamma = results_SC\$pv_gamma[, 1],
      qv_gamma = results_SC\$qv_gamma[, 1],
      pv_beta = results_SC\$pv_beta[, 1],
      qv_beta = results_SC\$qv_beta[, 1],
      pv_2part = results_SC\$pv_2part[, 1],
      qv_2part = results_SC\$qv_2part[, 1],
      stringsAsFactors = FALSE
    )
    write.csv(results_df, file = "sda_results_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SDAMS_MATRIX_BASED_ANALYSIS":',
        paste0('    SDAMS: ', as.character(packageVersion('SDAMS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_based_analysis.csv versions.yml
    """
}

workflow BIOC_SDAMS_MATRIX_BASED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ featureInfo, groupInfo ] ]

    main:
    BIOC_SDAMS_MATRIX_BASED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SDAMS_MATRIX_BASED_ANALYSIS.out.tables
    plots    = BIOC_SDAMS_MATRIX_BASED_ANALYSIS.out.plots
    objects  = BIOC_SDAMS_MATRIX_BASED_ANALYSIS.out.objects
    versions = BIOC_SDAMS_MATRIX_BASED_ANALYSIS.out.versions
}
